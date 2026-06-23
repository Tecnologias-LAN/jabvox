# frozen_string_literal: true

# Reporte "Bandejas (Informes)" (key: report_inboxes).
#
# Consolida la actividad de conversaciones agrupadas por bandeja de entrada
# (inbox). Todas las consultas arrancan SIEMPRE de la cuenta vía ActiveRecord
# (account.conversations / account.inboxes / ReportingEvent.where(account_id:)),
# sin `.all` global y sin SQL crudo con el account_id interpolado.
#
#   - conversations : account.conversations provee el universo. Se agrupa por
#                     inbox_id y se cuenta total / resueltas / abiertas / etc.
#                     status es enum (open/resolved/pending/snoozed).
#                     Ventana de fecha sobre created_at.
#   - inboxes       : account.inboxes resuelve nombre legible y channel_type por
#                     inbox_id (un único query, mapeado en Ruby).
#   - reporting_events : ReportingEvent.where(account_id: account.id) aporta los
#                     tiempos (first_response / reply_time / resolution) por
#                     inbox_id. value es numérico; created_at acota la ventana.
#
# date_from/date_to acotan created_at; se manejan nil (sin filtro de fecha).
class Jabvox::Analytics::Reports::ReportInboxesReportService
  # Eventos de reporting_events que aportan tiempos por bandeja.
  TIME_EVENT_NAMES = %w[first_response reply_time conversation_resolved].freeze

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
      by_event: build_by_event
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

  # ---- Scopes (siempre acotados a la cuenta) ------------------------------

  # Conversaciones de la cuenta + ventana por created_at.
  # Filtros: inbox_id, status (enum) y assignee_id (agente).
  def conversations_scope
    scope = account.conversations
    scope = scope.where('conversations.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('conversations.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
    scope = scope.where(status: filter_status) if filter_status
    scope = scope.where(assignee_id: filter_agent_id) if filter_agent_id
    scope
  end

  # Eventos de reporting de la cuenta + ventana por created_at.
  # Filtros: inbox_id y user_id (agente).
  def reporting_events_scope
    scope = ReportingEvent.where(account_id: account.id)
    scope = scope.where('reporting_events.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('reporting_events.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
    scope = scope.where(user_id: filter_agent_id) if filter_agent_id
    scope
  end

  # ---- Métricas agregadas -------------------------------------------------

  def build_summary
    counts_by_status = conversations_scope.group(:status).count

    {
      total_conversations: conversations_scope.count,
      resolved: status_count(counts_by_status, :resolved),
      open: status_count(counts_by_status, :open),
      pending: status_count(counts_by_status, :pending),
      snoozed: status_count(counts_by_status, :snoozed),
      active_inboxes: conversations_scope.distinct.count(:inbox_id)
    }
  end

  # Serie temporal diaria: conversaciones creadas por día.
  def build_series
    conversations_scope.group('DATE(conversations.created_at)').count.sort.map do |day, count|
      { date: day.to_s, conversations: count }
    end
  end

  # Una fila por inbox_id: total, resueltas, abiertas (y resto de estados),
  # resolviendo nombre y channel_type vía account.inboxes.
  def build_by_inbox
    total = conversations_scope.group(:inbox_id).count
    by_status = conversations_scope.group(:inbox_id, :status).count
    meta = inbox_meta(total.keys)

    rows = total.map do |inbox_id, count|
      info = meta[inbox_id] || {}
      {
        inbox_id: inbox_id,
        name: info[:name],
        channel_type: info[:channel_type],
        total: count,
        resolved: inbox_status_count(by_status, inbox_id, :resolved),
        open: inbox_status_count(by_status, inbox_id, :open),
        pending: inbox_status_count(by_status, inbox_id, :pending),
        snoozed: inbox_status_count(by_status, inbox_id, :snoozed)
      }
    end
    rows.sort_by { |row| -row[:total] }
  end

  # Tiempos promedio por bandeja a partir de reporting_events (value numérico),
  # uno por tipo de evento relevante. Se agrupa por inbox_id.
  def build_by_event
    rows = TIME_EVENT_NAMES.map do |event_name|
      scope = reporting_events_scope.where(name: event_name)
      by_inbox = scope.group(:inbox_id).average(:value)

      {
        name: event_name,
        events: scope.count,
        average_value: scope.average(:value)&.to_f,
        by_inbox: by_inbox.map { |inbox_id, avg| { inbox_id: inbox_id, average_value: avg&.to_f } }
      }
    end

    { available: true, source: 'reporting_events', rows: rows }
  end

  # ---- Helpers ------------------------------------------------------------

  # Conteo de un status en el group(:status) (summary). Tolera claves string
  # (label del enum) o entero (valor interno) según devuelva el group.
  def status_count(counts_by_status, status)
    counts_by_status[status.to_s].to_i + counts_by_status[conversation_status_value(status)].to_i
  end

  # Conteo de un status para una bandeja en el group(:inbox_id, :status).
  # Tolera la clave de status como string (label) o entero (valor del enum).
  def inbox_status_count(by_status, inbox_id, status)
    by_status[[inbox_id, status.to_s]].to_i + by_status[[inbox_id, conversation_status_value(status)]].to_i
  end

  # Valor interno del enum de Conversation para un status dado (entero).
  def conversation_status_value(status)
    Conversation.statuses[status.to_s]
  end

  # Nombre y channel_type de las bandejas observadas, en un único query acotado
  # a account.inboxes y mapeado por id.
  def inbox_meta(inbox_ids)
    ids = inbox_ids.compact
    return {} if ids.empty?

    account.inboxes.where(id: ids).pluck(:id, :name, :channel_type).each_with_object({}) do |(id, name, channel_type), acc|
      acc[id] = { name: name, channel_type: channel_type }
    end
  end
end
