# frozen_string_literal: true

# Reporte "Agentes" (key: agents).
#
# Consolida la actividad de cada agente (user_id) a partir de cinco fuentes,
# todas SIEMPRE acotadas a la cuenta vía ActiveRecord (sin SQL crudo con el
# account_id interpolado, sin `.all` global):
#
#   1. jabvox_dialer_state_logs -> tiempo/sesiones en cada estado del marcador.
#                                  Clave agente: user_id. Estado: `dialer_state`
#                                  (string libre). Fechas: started_at/ended_at.
#                                  Sin asociación en Account -> se acota con
#                                  JabvoxDialerStateLog.where(account_id: account.id).
#   2. jabvox_app_state_logs    -> tiempo/sesiones en cada estado de la app.
#                                  Clave agente: user_id. Estado: app_state_id
#                                  (nullable; el nombre vive en jabvox_app_states).
#                                  Fechas: started_at/ended_at. Sin asociación en
#                                  Account -> JabvoxAppStateLog.where(account_id:).
#   3. jabvox_call_logs         -> llamadas individuales por agente. Clave: user_id.
#                                  Fecha relevante: called_at (fallback created_at).
#                                  NO tiene duración ni ended_at.
#   4. jabvox_ai_chat_messages  -> mensajes de chat IA por agente. Clave: user_id.
#                                  Solo created_at. Roles en role_jabvox.
#   5. jabvox_internal_chats    -> chats internos. Clave de creador: created_by_id.
#                                  Los mensajes viven en jabvox_internal_messages
#                                  (sender_id = agente; NO tiene account_id, se
#                                  une por chat_id contra los chats de la cuenta).
#
# Salida: una fila por user_id en `by_agent` (merge en Ruby), más una serie
# temporal de actividad y un agregado de estados.
class Jabvox::Analytics::Reports::AgentsReportService
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
      by_agent: build_by_agent,
      by_dialer_state: build_by_dialer_state,
      by_app_state: build_by_app_state
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # ---- Filtros adicionales -----------------------------------------------

  # Id de agente solicitado (agent_id o user_id en @filters). nil si no aplica.
  def filter_agent_id
    @filter_agent_id ||= begin
      raw = filters['agent_id'].presence || filters['user_id'].presence
      raw && raw.to_i
    end
  end

  def filter_dialer_state
    filters['status'].presence
  end

  # ---- Scopes por fuente (siempre acotados a la cuenta) -------------------

  # Estados del marcador. Acotado a la cuenta + ventana por started_at.
  def dialer_state_logs
    scope = JabvoxDialerStateLog.where(account_id: account.id)
    scope = scope.where('jabvox_dialer_state_logs.started_at >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_dialer_state_logs.started_at <= ?', date_to) if date_to.present?
    scope = scope.where(user_id: filter_agent_id) if filter_agent_id
    scope = scope.where(dialer_state: filter_dialer_state) if filter_dialer_state
    scope
  end

  # Estados de la app. Acotado a la cuenta + ventana por started_at.
  def app_state_logs
    scope = JabvoxAppStateLog.where(account_id: account.id)
    scope = scope.where('jabvox_app_state_logs.started_at >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_app_state_logs.started_at <= ?', date_to) if date_to.present?
    scope = scope.where(user_id: filter_agent_id) if filter_agent_id
    scope
  end

  # Llamadas individuales. Acotado a la cuenta + ventana por called_at.
  def call_logs
    scope = account.jabvox_call_logs
    scope = scope.where('jabvox_call_logs.called_at >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_call_logs.called_at <= ?', date_to) if date_to.present?
    scope = scope.where(user_id: filter_agent_id) if filter_agent_id
    scope
  end

  # Mensajes de chat IA. Acotado a la cuenta + ventana por created_at.
  def ai_chat_messages
    scope = account.jabvox_ai_chat_messages
    scope = scope.where('jabvox_ai_chat_messages.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_ai_chat_messages.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(user_id: filter_agent_id) if filter_agent_id
    scope
  end

  # Chats internos creados. Acotado a la cuenta + ventana por created_at.
  def internal_chats
    scope = account.jabvox_internal_chats
    scope = scope.where('jabvox_internal_chats.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_internal_chats.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(created_by_id: filter_agent_id) if filter_agent_id
    scope
  end

  # Mensajes internos enviados. La tabla no tiene account_id, por eso se acota
  # uniéndola a los chats internos de la cuenta (chat_id). La ventana de fecha
  # se aplica sobre el created_at del propio mensaje.
  def internal_messages
    scope = JabvoxInternalMessage
            .joins(:chat)
            .where(jabvox_internal_chats: { account_id: account.id })
    scope = scope.where('jabvox_internal_messages.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_internal_messages.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(sender_id: filter_agent_id) if filter_agent_id
    scope
  end

  # ---- Métricas agregadas ------------------------------------------------

  def build_summary
    {
      active_agents: active_agent_ids.size,
      total_calls: call_logs.count,
      dialer_sessions: dialer_state_logs.count,
      app_state_sessions: app_state_logs.count,
      ai_chat_messages: ai_chat_messages.count,
      internal_chats_created: internal_chats.count,
      internal_messages_sent: internal_messages.count
    }
  end

  # Serie temporal por día: llamadas y mensajes IA (las dos fuentes con una
  # única fecha de evento clara por fila). Los *_state_logs son intervalos, por
  # eso no se mezclan en esta serie diaria de "eventos".
  def build_series
    calls = call_logs.group('DATE(jabvox_call_logs.called_at)').count
    ai = ai_chat_messages.group('DATE(jabvox_ai_chat_messages.created_at)').count

    days = (calls.keys + ai.keys).compact.uniq.sort
    days.map do |day|
      {
        date: day.to_s,
        calls: calls[day].to_i,
        ai_chat_messages: ai[day].to_i
      }
    end
  end

  # Una fila por user_id (merge en Ruby de las cinco fuentes).
  def build_by_agent
    counts = agent_counts_by_source
    agent_ids = counts.values.flat_map(&:keys).compact.uniq

    rows = agent_ids.map { |agent_id| agent_row(agent_id, counts) }
    rows.sort_by { |row| -total_activity(row) }
  end

  # Conteos por agente para cada fuente, indexados por el id del agente.
  def agent_counts_by_source
    {
      calls: call_logs.group(:user_id).count,
      dialer_sessions: dialer_state_logs.group(:user_id).count,
      app_state_sessions: app_state_logs.group(:user_id).count,
      ai_chat_messages: ai_chat_messages.group(:user_id).count,
      internal_chats_created: internal_chats.group(:created_by_id).count,
      internal_messages_sent: internal_messages.group(:sender_id).count
    }
  end

  def agent_row(agent_id, counts)
    row = { agent_id: agent_id }
    counts.each { |metric, by_user| row[metric] = by_user[agent_id].to_i }
    row
  end

  # Agregado por estado del marcador. `dialer_state` es un string libre en la
  # propia tabla, así que se cuenta directamente.
  def build_by_dialer_state
    rows = dialer_state_logs.group(:dialer_state).count.map do |state, count|
      { dialer_state: state, sessions: count }
    end
    rows = rows.sort_by { |row| -row[:sessions] }

    { available: true, source: 'jabvox_dialer_state_logs', rows: rows }
  end

  # Agregado por estado de la app. app_state_id es nullable y el nombre legible
  # vive en jabvox_app_states; se resuelve con un único query acotado a la
  # cuenta y se mapea por id (las filas sin app_state_id quedan como nil).
  def build_by_app_state
    counts = app_state_logs.group(:app_state_id).count
    names = account.jabvox_app_states.pluck(:id, :name).to_h

    rows = counts.map do |state_id, count|
      {
        app_state_id: state_id,
        name: state_id && names[state_id],
        sessions: count
      }
    end
    rows = rows.sort_by { |row| -row[:sessions] }

    { available: true, source: 'jabvox_app_state_logs', rows: rows }
  end

  # ---- Helpers -----------------------------------------------------------

  def total_activity(row)
    row.except(:agent_id).values.sum
  end

  # Conjunto de agentes "activos" en la ventana: aparecen en al menos una fuente.
  def active_agent_ids
    (
      call_logs.distinct.pluck(:user_id) +
      dialer_state_logs.distinct.pluck(:user_id) +
      app_state_logs.distinct.pluck(:user_id) +
      ai_chat_messages.distinct.pluck(:user_id) +
      internal_chats.distinct.pluck(:created_by_id) +
      internal_messages.distinct.pluck(:sender_id)
    ).compact.uniq
  end
end
