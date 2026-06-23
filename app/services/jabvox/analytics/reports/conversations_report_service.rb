# frozen_string_literal: true

# Reporte interno "Conversaciones" (key: conversations).
#
# Fuentes (todas con scoping obligatorio por cuenta vía ActiveRecord):
#   - conversations            (account.conversations)         -> status enum, team_id, inbox_id, created_at
#   - reporting_events         (ReportingEvent.where(account_id:)) -> métricas de tiempos/resolución (name + value)
#   - csat_survey_responses    (account.csat_survey_responses) -> rating 1..5
#   - taggings                 (acotado a conversaciones de la cuenta vía taggable_id IN)
#
# Notas de esquema:
#   - conversations.status es un enum entero { open: 0, resolved: 1, pending: 2, snoozed: 3 }.
#     Se agrupa por el valor entero y se mapea al nombre legible con Conversation.statuses.invert.
#   - taggings NO tiene account_id; el scoping se hereda restringiendo taggable_id a las
#     conversaciones de la cuenta (taggable_type = 'Conversation').
class Jabvox::Analytics::Reports::ConversationsReportService
  TAGGABLE_TYPE = 'Conversation'

  def initialize(account:, date_from: nil, date_to: nil, filters: {})
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
    @date_from = date_from
    @date_to = date_to
    @filters = filters || {}
  end

  def call
    {
      summary: summary,
      series: series,
      by_status: by_status,
      by_team: by_team,
      by_inbox: by_inbox,
      reporting_events: reporting_events_section,
      csat: csat_section,
      by_label: by_label
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

  def filter_team_id
    @filter_team_id ||= filters['team_id'].presence&.to_i
  end

  # Conversaciones de la cuenta acotadas por created_at. Siempre arranca de la asociación de la cuenta.
  # Filtros: assignee_id (agente), status (enum), inbox_id y team_id.
  def scoped_conversations
    relation = account.conversations
    relation = relation.where('conversations.created_at >= ?', date_from) if date_from.present?
    relation = relation.where('conversations.created_at <= ?', date_to) if date_to.present?
    relation = relation.where(assignee_id: filter_agent_id) if filter_agent_id
    relation = relation.where(status: filter_status) if filter_status
    relation = relation.where(inbox_id: filter_inbox_id) if filter_inbox_id
    relation = relation.where(team_id: filter_team_id) if filter_team_id
    relation
  end

  # Eventos de reporte de la cuenta acotados por created_at. Scoping explícito por account_id.
  # Filtros: user_id (agente) e inbox_id donde existan.
  def scoped_reporting_events
    relation = ReportingEvent.where(account_id: account.id)
    relation = relation.where('reporting_events.created_at >= ?', date_from) if date_from.present?
    relation = relation.where('reporting_events.created_at <= ?', date_to) if date_to.present?
    relation = relation.where(user_id: filter_agent_id) if filter_agent_id
    relation = relation.where(inbox_id: filter_inbox_id) if filter_inbox_id
    relation
  end

  # Respuestas CSAT de la cuenta acotadas por created_at. Siempre arranca de la asociación de la cuenta.
  # Filtro: assigned_agent_id (agente).
  def scoped_csat
    relation = account.csat_survey_responses
    relation = relation.where('csat_survey_responses.created_at >= ?', date_from) if date_from.present?
    relation = relation.where('csat_survey_responses.created_at <= ?', date_to) if date_to.present?
    relation = relation.where(assigned_agent_id: filter_agent_id) if filter_agent_id
    relation
  end

  def summary
    counts = status_counts
    {
      total_conversations: scoped_conversations.count,
      open: counts.fetch('open', 0),
      resolved: counts.fetch('resolved', 0),
      pending: counts.fetch('pending', 0),
      snoozed: counts.fetch('snoozed', 0),
      teams_with_conversations: scoped_conversations.where.not(team_id: nil).distinct.count(:team_id),
      inboxes_with_conversations: scoped_conversations.distinct.count(:inbox_id),
      csat_responses: scoped_csat.count,
      csat_average_rating: csat_average_rating
    }
  end

  # Serie temporal diaria de conversaciones por fecha de creación.
  def series
    rows = scoped_conversations
           .group('DATE(conversations.created_at)')
           .order(Arel.sql('DATE(conversations.created_at)'))
           .count

    rows.map { |date, count| { date: date.to_s, count: count } }
  end

  # Desglose por estado, mapeando el entero del enum al nombre legible.
  def by_status
    status_counts.map { |status, count| { status: status, count: count } }
  end

  # Desglose por equipo (team_id). Las conversaciones sin equipo quedan como team_id nil.
  def by_team
    counts = scoped_conversations.group(:team_id).count
    names = account.teams.pluck(:id, :name).to_h

    rows = counts.map do |team_id, count|
      { team_id: team_id, name: team_id && names[team_id], count: count }
    end
    rows.sort_by { |row| -row[:count] }
  end

  # Desglose por bandeja (inbox_id).
  def by_inbox
    counts = scoped_conversations.group(:inbox_id).count
    names = account.inboxes.pluck(:id, :name).to_h

    rows = counts.map do |inbox_id, count|
      { inbox_id: inbox_id, name: names[inbox_id], count: count }
    end
    rows.sort_by { |row| -row[:count] }
  end

  # Agregado de eventos de reporte por nombre de evento: conteo, promedio y total del value.
  def reporting_events_section
    rows = scoped_reporting_events
           .group(:name)
           .pluck(:name, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(AVG(value), 0)'), Arel.sql('COALESCE(SUM(value), 0)'))
           .map do |name, count, avg, sum|
             { name: name, count: count, average_value: avg.to_f.round(2), total_value: sum.to_f.round(2) }
           end
    rows = rows.sort_by { |row| -row[:count] }

    { available: true, source: 'reporting_events', rows: rows }
  end

  # Sección CSAT: distribución por rating y promedio.
  def csat_section
    distribution = scoped_csat
                   .group(:rating)
                   .count
                   .map { |rating, count| { rating: rating, count: count } }
                   .sort_by { |row| row[:rating] }

    {
      available: true,
      total_responses: scoped_csat.count,
      average_rating: csat_average_rating,
      by_rating: distribution
    }
  end

  # Etiquetas de conversación. taggings no tiene account_id: se acota restringiendo
  # taggable_id a las conversaciones de la cuenta (subconsulta select(:id)) y
  # taggable_type a 'Conversation'. NUNCA consulta global de taggings.
  def by_label
    counts = ActsAsTaggableOn::Tagging
             .where(taggable_type: TAGGABLE_TYPE, context: 'labels')
             .where(taggable_id: scoped_conversations.select(:id))
             .group(:tag_id)
             .count
    names = tag_names(counts.keys)

    rows = counts.map { |tag_id, count| { tag_id: tag_id, name: names[tag_id], count: count } }
    rows = rows.sort_by { |row| -row[:count] }

    { available: true, source: 'taggings', rows: rows }
  end

  # Nombres de etiquetas en una sola query. Los ids provienen de taggings ya
  # acotadas a conversaciones de la cuenta.
  def tag_names(tag_ids)
    return {} if tag_ids.empty?

    ActsAsTaggableOn::Tag.where(id: tag_ids).pluck(:id, :name).to_h
  end

  # ---- Helpers -----------------------------------------------------------

  # Conteo por estado mapeado al nombre legible del enum { open, resolved, pending, snoozed }.
  def status_counts
    names = Conversation.statuses.invert
    scoped_conversations.group(:status).count.transform_keys { |value| names[value] || value.to_s }
  end

  def csat_average_rating
    average = scoped_csat.average(:rating)
    average ? average.to_f.round(2) : 0.0
  end
end
