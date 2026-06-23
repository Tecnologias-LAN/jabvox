# frozen_string_literal: true

# Reporte "Agentes (Informes)" (key: report_agents) para el módulo Analytics
# de Jabvox.
#
# A diferencia de AgentsReportService (que mide actividad operativa del marcador,
# app states, llamadas y chats), este reporte mide el RENDIMIENTO de cada agente
# a partir de los eventos de reporting (reporting_events) y la satisfacción
# (csat_survey_responses), que es la fuente canónica de las métricas de informes.
#
# Fuentes:
#   - reporting_events        : eventos numéricos por agente (user_id). Los `name`
#                               relevantes son 'conversation_resolved' (cuenta),
#                               'first_response' y 'reply_time' (promedios de
#                               value en segundos). Tiene account_id propio.
#   - conversations           : conversaciones de la cuenta (assignee_id => agente)
#                               para conteo de asignadas/resueltas por agente.
#   - csat_survey_responses   : rating 1..5 por assigned_agent_id => CSAT promedio.
#
# SEGURIDAD: toda consulta arranca de account.<assoc> o where(account_id:
# account.id). reporting_events se acota con ReportingEvent.where(account_id:
# account.id). No hay SQL crudo con account_id interpolado ni `.all` global.
#
# date_from/date_to acotan created_at de cada fuente; nil => sin filtro.
class Jabvox::Analytics::Reports::ReportAgentsReportService
  RESOLVED_EVENT = 'conversation_resolved'
  FIRST_RESPONSE_EVENT = 'first_response'
  REPLY_TIME_EVENT = 'reply_time'

  def initialize(account:, date_from: nil, date_to: nil, filters: {})
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
    @date_from = date_from
    @date_to = date_to
    @filters = filters || {}
  end

  def call
    {
      summary: build_summary,
      series: build_series,
      by_agent: build_by_agent
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Id de agente solicitado (agent_id o user_id en @filters).
  def filter_agent_id
    @filter_agent_id ||= begin
      raw = filters['agent_id'].presence || filters['user_id'].presence
      raw && raw.to_i
    end
  end

  def filter_status
    filters['status'].presence
  end

  def filter_inbox_id
    @filter_inbox_id ||= filters['inbox_id'].presence&.to_i
  end

  # ---- Scopes por fuente (siempre acotados a la cuenta) -------------------

  # Eventos de reporting. Acotado a la cuenta + ventana por created_at.
  # Filtros: user_id (agente) e inbox_id.
  def reporting_events
    scope = ReportingEvent.where(account_id: account.id)
    scope = scope.where('reporting_events.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('reporting_events.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(user_id: filter_agent_id) if filter_agent_id
    scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
    scope
  end

  # Conversaciones de la cuenta. Acotado por la asociación + ventana created_at.
  # Filtros: assignee_id (agente), status (enum) e inbox_id.
  def conversations
    scope = account.conversations
    scope = scope.where('conversations.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('conversations.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(assignee_id: filter_agent_id) if filter_agent_id
    scope = scope.where(status: filter_status) if filter_status
    scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
    scope
  end

  # Respuestas CSAT. Acotado por la asociación + ventana created_at.
  # Filtro: assigned_agent_id (agente).
  def csat_responses
    scope = account.csat_survey_responses
    scope = scope.where('csat_survey_responses.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('csat_survey_responses.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(assigned_agent_id: filter_agent_id) if filter_agent_id
    scope
  end

  # ---- Métricas agregadas ------------------------------------------------

  def build_summary
    csat = csat_responses
    csat_count = csat.count
    {
      active_agents: active_agent_ids.size,
      resolved_conversations: resolved_events_by_agent.values.sum,
      avg_first_response_seconds: round_or_nil(reporting_events.where(name: FIRST_RESPONSE_EVENT).average(:value)),
      avg_reply_time_seconds: round_or_nil(reporting_events.where(name: REPLY_TIME_EVENT).average(:value)),
      csat_responses: csat_count,
      avg_csat_rating: csat_count.positive? ? round_or_nil(csat.average(:rating)) : nil
    }
  end

  # Serie temporal diaria: conversaciones resueltas (eventos) por día.
  def build_series
    resolved = reporting_events.where(name: RESOLVED_EVENT)
                               .group('DATE(reporting_events.created_at)').count
    days = resolved.keys.compact.sort
    days.map do |day|
      {
        date: day.to_s,
        resolved_conversations: resolved[day].to_i
      }
    end
  end

  # Una fila por agente (merge en Ruby de las fuentes). Orden: resueltas desc.
  def build_by_agent
    resolved = resolved_events_by_agent
    first_response = avg_event_by_agent(FIRST_RESPONSE_EVENT)
    reply_time = avg_event_by_agent(REPLY_TIME_EVENT)
    assigned = conversations.where.not(assignee_id: nil).group(:assignee_id).count
    csat_avg = csat_responses.where.not(assigned_agent_id: nil).group(:assigned_agent_id).average(:rating)

    agent_ids = (resolved.keys + first_response.keys + reply_time.keys + assigned.keys + csat_avg.keys).compact.uniq
    names = agent_names(agent_ids)

    rows = agent_ids.map do |agent_id|
      {
        agent_id: agent_id,
        name: names[agent_id],
        resolved_conversations: resolved[agent_id].to_i,
        assigned_conversations: assigned[agent_id].to_i,
        avg_first_response_seconds: round_or_nil(first_response[agent_id]),
        avg_reply_time_seconds: round_or_nil(reply_time[agent_id]),
        avg_csat_rating: round_or_nil(csat_avg[agent_id])
      }
    end

    rows.sort_by { |row| -row[:resolved_conversations] }
  end

  # ---- Helpers -----------------------------------------------------------

  # Conversaciones resueltas por agente (conteo de eventos conversation_resolved).
  def resolved_events_by_agent
    reporting_events.where(name: RESOLVED_EVENT).where.not(user_id: nil).group(:user_id).count
  end

  # Promedio de value para un tipo de evento, indexado por user_id.
  def avg_event_by_agent(event_name)
    reporting_events.where(name: event_name).where.not(user_id: nil).group(:user_id).average(:value)
  end

  # Agentes "activos": aparecen en al menos una fuente dentro de la ventana.
  def active_agent_ids
    (
      reporting_events.where.not(user_id: nil).distinct.pluck(:user_id) +
      conversations.where.not(assignee_id: nil).distinct.pluck(:assignee_id) +
      csat_responses.where.not(assigned_agent_id: nil).distinct.pluck(:assigned_agent_id)
    ).compact.uniq
  end

  # Nombres de agentes en una sola query. Los ids ya provienen de fuentes
  # acotadas a la cuenta, así que no exponen otras cuentas.
  def agent_names(agent_ids)
    return {} if agent_ids.empty?

    User.where(id: agent_ids).pluck(:id, :name).to_h
  end

  def round_or_nil(value)
    value && value.to_f.round(2)
  end
end
