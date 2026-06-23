# frozen_string_literal: true

# Reporte interno "Resumen" (key: overview) para el módulo Analytics de Jabvox.
#
# Consolida los KPIs globales de la cuenta a partir de tres fuentes, todas
# SIEMPRE acotadas a la cuenta vía ActiveRecord (sin `.all` global, sin SQL
# crudo con el account_id interpolado):
#
#   1. conversations          : volumen y estado (open/resolved/pending/snoozed),
#                               vía account.conversations. Fecha: created_at.
#   2. reporting_events       : eventos de operación. Acotado con
#                               ReportingEvent.where(account_id: account.id).
#                               Se usan los nombres 'conversation_resolved'
#                               (conteo), 'first_response' (promedio de value) y
#                               'reply_time' (promedio de value). Fecha: created_at.
#   3. csat_survey_responses  : satisfacción (rating 1..5), vía
#                               account.csat_survey_responses. Fecha: created_at.
#
# Desgloses auxiliares:
#   - by_inbox  : conversaciones por inbox (id/nombre desde account.inboxes).
#   - by_label  : conversaciones por etiqueta. Las taggings NUNCA se consultan
#                 global: se filtra taggable_type='Conversation' y taggable_id
#                 IN (account.conversations select :id), por lo que el account_id
#                 viaja siempre por el query.
#
# date_from/date_to acotan created_at de cada fuente; si son nil no se filtra.
class Jabvox::Analytics::Reports::OverviewReportService
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
      by_inbox: build_by_inbox,
      by_label: build_by_label
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

  # Conversaciones de la cuenta + ventana por created_at.
  # Filtros: assignee_id (agente), status (enum) e inbox_id.
  def conversations_scope
    scope = account.conversations
    scope = scope.where('conversations.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('conversations.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(assignee_id: filter_agent_id) if filter_agent_id
    scope = scope.where(status: filter_status) if filter_status
    scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
    scope
  end

  # Eventos de reporte de la cuenta + ventana por created_at.
  # Filtros: user_id (agente) e inbox_id.
  def reporting_events_scope
    scope = ReportingEvent.where(account_id: account.id)
    scope = scope.where('reporting_events.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('reporting_events.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(user_id: filter_agent_id) if filter_agent_id
    scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
    scope
  end

  # Respuestas CSAT de la cuenta + ventana por created_at. Filtro: assigned_agent_id.
  def csat_scope
    scope = account.csat_survey_responses
    scope = scope.where('csat_survey_responses.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('csat_survey_responses.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(assigned_agent_id: filter_agent_id) if filter_agent_id
    scope
  end

  # ---- Métricas agregadas -------------------------------------------------

  def build_summary
    conversations_summary.merge(events_summary).merge(csat_summary)
  end

  # KPIs de volumen y estado de conversaciones (open/resolved/pending/snoozed).
  def conversations_summary
    total = conversations_scope.count
    by_status = conversations_scope.group(:status).count
    resolved = by_status['resolved'].to_i

    {
      total_conversations: total,
      open_conversations: by_status['open'].to_i,
      resolved_conversations: resolved,
      pending_conversations: by_status['pending'].to_i,
      snoozed_conversations: by_status['snoozed'].to_i,
      resolution_rate: total.positive? ? (resolved.to_f / total * 100).round(2) : 0.0
    }
  end

  # KPIs derivados de reporting_events (conteo de resueltos, tiempos promedio).
  def events_summary
    {
      resolved_events: reporting_events_scope.where(name: RESOLVED_EVENT).count,
      avg_first_response_seconds: avg_event_value(FIRST_RESPONSE_EVENT),
      avg_reply_time_seconds: avg_event_value(REPLY_TIME_EVENT)
    }
  end

  # KPIs de satisfacción (csat_survey_responses, rating 1..5).
  def csat_summary
    csat = csat_scope
    {
      csat_responses: csat.count,
      avg_csat_rating: csat.average(:rating)&.round(2)
    }
  end

  # Serie temporal diaria de conversaciones creadas (conversations.created_at).
  def build_series
    conversations_scope.group('DATE(conversations.created_at)').count.sort.map do |day, count|
      { date: day.to_s, conversations: count }
    end
  end

  # Conversaciones por inbox. Los nombres se resuelven con una única query
  # acotada a la cuenta (account.inboxes); los ids ya provienen de
  # conversaciones de la cuenta.
  def build_by_inbox
    counts = conversations_scope.group(:inbox_id).count
    names = account.inboxes.pluck(:id, :name).to_h

    rows = counts.map do |inbox_id, count|
      { inbox_id: inbox_id, name: names[inbox_id], conversations: count }
    end
    rows.sort_by { |row| -row[:conversations] }
  end

  # Conversaciones por etiqueta. SEGURIDAD: las taggings se filtran por
  # taggable_type='Conversation' y taggable_id IN (conversaciones de la cuenta),
  # nunca de forma global. La ventana de fecha ya viaja dentro de
  # conversations_scope (subselect de ids).
  def build_by_label
    counts = ActsAsTaggableOn::Tagging
             .where(taggable_type: 'Conversation', context: 'labels')
             .where(taggable_id: conversations_scope.select(:id))
             .group(:tag_id).count
    names = tag_names(counts.keys)

    rows = counts.map do |tag_id, count|
      { tag_id: tag_id, name: names[tag_id], conversations: count }
    end
    rows.sort_by { |row| -row[:conversations] }
  end

  # ---- Helpers ------------------------------------------------------------

  # Promedio de `value` para un nombre de evento dado. nil si no hay filas.
  def avg_event_value(event_name)
    reporting_events_scope.where(name: event_name).average(:value)&.round(2)
  end

  # Nombres de etiquetas en una sola query. Los ids provienen de taggings ya
  # acotadas a conversaciones de la cuenta.
  def tag_names(tag_ids)
    return {} if tag_ids.empty?

    ActsAsTaggableOn::Tag.where(id: tag_ids).pluck(:id, :name).to_h
  end
end
