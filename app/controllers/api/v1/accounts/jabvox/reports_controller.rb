# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::ReportsController < Api::V1::Accounts::Jabvox::BaseController
  # Multi-module report panel: gated by per-action permissions (reports_view)
  # and per-action module checks (ensure_products_module), not a single flag.
  jabvox_feature :none
  include JabvoxPermissions

  # Report views are gated by jabvox_reports_view. set_dialer_state is excluded:
  # it lets the current user set their OWN presence, which any agent may do.
  before_action :ensure_reports_permission, except: [:set_dialer_state]
  # The products report only exists while the products module is active.
  before_action :ensure_products_module, only: [:products]

  def products
    orders = Current.account.jabvox_orders
    orders = orders.where(doc_type: params[:doc_type]) if params[:doc_type].present?
    orders = orders.where(status: params[:status]) if params[:status].present?
    if params[:date_from].present?
      orders = orders.where('jabvox_orders.created_at >= ?',
                            Time.zone.parse(params[:date_from]).beginning_of_day.utc)
    end
    if params[:date_to].present?
      orders = orders.where('jabvox_orders.created_at <= ?',
                            Time.zone.parse(params[:date_to]).end_of_day.utc)
    end
    orders = orders.includes(:contact, conversation: [:assignee]).order(created_at: :desc)

    render json: { orders: orders.map { |o| serialize_order(o) } }
  end

  def agents
    date_range = build_date_range
    account_id = Current.account.id

    messages_sent = Message.where(account_id: account_id, message_type: 1, private: false, sender_type: 'User')
                           .where(created_at: date_range).reorder(nil).group(:sender_id).count

    # Notas privadas del agente, separadas en dos:
    #   - Gestiones: notas con estado de gestión (creadas desde el apartado de
    #     notas del detalle del lead / click-to-call / dialer). Se identifican
    #     porque tienen filas en jabvox_management_answers ligadas al message_id.
    #   - Notas: notas privadas normales escritas en el chat, SIN estado de gestión.
    private_notes = Message.where(account_id: account_id, private: true, sender_type: 'User')
                           .where(created_at: date_range)
    # Subquery (no pluck): message_ids that carry a management state. A NOT EXISTS
    # keeps this scalable — no list of ids is loaded into memory.
    management_ids = JabvoxManagementAnswer.where(account_id: account_id)
                                           .where('jabvox_management_answers.message_id = messages.id')
                                           .select(1)
    managements_added = private_notes.where('EXISTS (?)', management_ids)
                                     .reorder(nil).group(:sender_id).count
    notes_added = private_notes.where('NOT EXISTS (?)', management_ids)
                               .reorder(nil).group(:sender_id).count

    orders_placed = JabvoxOrder.joins(:conversation)
                               .where(account_id: account_id)
                               .where(jabvox_orders: { created_at: date_range })
                               .group('conversations.assignee_id').count

    calls_made = JabvoxDialerCallLog.where(account_id: account_id)
                                    .where(created_at: date_range)
                                    .group(:agent_id_jabvox).count

    # Conversaciones resueltas por agente (número de resoluciones), de
    # reporting_events name='conversation_resolved' (user_id = assignee).
    resolved_count = ReportingEvent.where(account_id: account_id, name: 'conversation_resolved')
                                   .where(created_at: date_range)
                                   .reorder(nil).group(:user_id).count

    # Conversaciones distintas en las que el agente habló (personas, contadas por
    # conversación, no por mensaje): conversaciones donde envió >=1 mensaje saliente.
    conversations_count = Message.where(account_id: account_id, message_type: 1,
                                        private: false, sender_type: 'User')
                                 .where(created_at: date_range)
                                 .reorder(nil).group(:sender_id)
                                 .distinct.count(:conversation_id)

    state_times = build_state_times(account_id, date_range)
    current_states = build_current_states(account_id)
    app_states = build_state_columns(state_times)

    open_range = params[:date_to].blank?

    users = Current.account.users.order(:name)
    human_rows = users.map do |u|
      {
        id: u.id,
        name: u.name,
        email: u.email,
        avatar_url: u.avatar_url,
        is_hermes: false,
        resolved_count: resolved_count[u.id] || 0,
        conversations_count: conversations_count[u.id] || 0,
        messages_sent: messages_sent[u.id] || 0,
        notes_added: notes_added[u.id] || 0,
        managements_added: managements_added[u.id] || 0,
        orders_placed: orders_placed[u.id] || 0,
        calls_made: calls_made[u.id] || 0,
        state_times: state_times[u.id] || {},
        current_state_key: open_range ? current_states[u.id] : nil
      }
    end

    render json: {
      fetched_at: Time.current.iso8601,
      open_range: open_range,
      # Filas humanas + una fila por cada agente de Hermes (bot), para que la actividad
      # automatizada figure junto a la de las personas.
      agents: human_rows + hermes_agent_rows(account_id, date_range),
      app_states: app_states
    }
  end

  # Construye una fila "tipo agente" por cada agente de Hermes activo, con métricas
  # derivadas de la auditoría (JabvoxHermesActionLog). Solo acciones exitosas cuentan
  # como trabajo realizado; el mapeo tool→columna es explícito para no adivinar.
  def hermes_agent_rows(account_id, date_range)
    success = JabvoxHermesActionLog.where(account_id: account_id, status_jabvox: 'success',
                                          created_at: date_range)
    return [] unless success.exists?

    by_identity_tool = success.reorder(nil).group(:hermes_identity_jabvox, :tool_jabvox).count
    # tool → columna del reporte que representa
    msg_tools   = %w[reply_conversation]
    note_tools  = %w[add_private_note create_contact_note]
    mgmt_tools  = %w[create_management_state update_management_state]
    # create_order/update_order se añadirán con el lote de tools de escritura de pedidos.
    order_tools = %w[create_order update_order]

    identities = by_identity_tool.keys.map(&:first).uniq
    identities.map do |identity|
      tally = ->(tools) { tools.sum { |t| by_identity_tool[[identity, t]].to_i } }
      total = by_identity_tool.select { |(ident, _t), _n| ident == identity }.values.sum
      {
        id: "hermes:#{identity}",
        name: "🤖 #{identity.presence || 'Manty'}",
        email: 'Manty (IA)',
        avatar_url: nil,
        is_hermes: true,
        resolved_count: 0,
        conversations_count: 0,
        messages_sent: tally.call(msg_tools),
        notes_added: tally.call(note_tools),
        managements_added: tally.call(mgmt_tools),
        orders_placed: tally.call(order_tools),
        calls_made: 0,
        hermes_total_actions: total,
        state_times: {},
        current_state_key: nil
      }
    end
  end

  DIALER_STATES = [
    { key: 'inactive',    name: 'Inactivo',          color: '#94a3b8' },
    { key: 'connected',   name: 'Conectado',          color: '#22c55e' },
    { key: 'waiting',     name: 'Esperando llamada',  color: '#f59e0b' },
    { key: 'in_call',     name: 'En llamada',         color: '#3b82f6' },
    { key: 'in_comments', name: 'En comentarios',     color: '#8b5cf6' }
  ].freeze

  def dialer
    date_range = build_date_range
    account_id = Current.account.id
    logs = JabvoxDialerCallLog.where(account_id: account_id, created_at: date_range)

    by_agent_calls = logs.group(:agent_id_jabvox)
                         .select('agent_id_jabvox,
                                  count(*) as total_calls,
                                  coalesce(sum(case when status_jabvox=\'answered\' then 1 else 0 end),0) as answered_calls,
                                  coalesce(sum(duration_jabvox),0) as total_duration,
                                  count(case when notes_jabvox IS NOT NULL AND notes_jabvox != \'\' then 1 end) as notes_in_calls')
    by_status = logs.group(:status_jabvox).count

    state_times    = build_dialer_state_times(account_id, date_range)
    current_states = build_dialer_current_states(account_id)
    open_range     = params[:date_to].blank?

    users = Current.account.users.order(:name)
    calls_by_uid = by_agent_calls.index_by(&:agent_id_jabvox)

    render json: {
      fetched_at: Time.current.iso8601,
      open_range: open_range,
      dialer_states: DIALER_STATES,
      agents: users.map do |u|
        row = calls_by_uid[u.id]
        {
          id: u.id,
          name: u.name,
          email: u.email,
          avatar_url: u.avatar_url,
          total_calls: row&.total_calls.to_i,
          answered_calls: row&.answered_calls.to_i,
          total_duration: row&.total_duration.to_i,
          notes_in_calls: row&.notes_in_calls.to_i,
          state_times: state_times[u.id] || {},
          current_dialer_state_key: open_range ? current_states[u.id] : nil
        }
      end,
      by_status: by_status,
      total_calls: logs.count,
      total_answered: logs.where(status_jabvox: 'answered').count,
      total_duration: logs.sum(:duration_jabvox)
    }
  end

  def agent_status
    online_users = OnlineStatusTracker.get_available_users(Current.account.id)
    pause_names = Current.account.jabvox_dialer_states.pluck(:id, :name).to_h
    campaign_names = Current.account.jabvox_dialer_campaigns.pluck(:id, :name_jabvox).to_h

    account_users = Current.account.account_users
                           .includes(:user)
                           .joins('LEFT JOIN jabvox_app_states ON jabvox_app_states.id = account_users.jabvox_app_state_id')
                           .select('account_users.*, jabvox_app_states.name as app_state_name, jabvox_app_states.color as app_state_color')

    render json: {
      agents: account_users.map do |au|
        real_availability = online_users[au.user_id.to_s] || 'offline'
        dialer = dialer_live_state(au.user_id, pause_names, campaign_names)
        {
          id: au.user_id,
          name: au.user.name,
          email: au.user.email,
          avatar_url: au.user.avatar_url,
          availability: real_availability,
          app_state_id: au.jabvox_app_state_id,
          app_state_name: au.app_state_name,
          app_state_color: au.app_state_color,
          app_state_since: au.jabvox_app_state_changed_at,
          dialer_state: dialer[:state],
          dialer_state_since: dialer[:since],
          dialer_pause_name: dialer[:pause_name],
          dialer_campaign: dialer[:campaign]
        }
      end
    }
  end

  def set_dialer_state
    # Fuente única de escritura de estados (comparte lógica con el ciclo de vida
    # del dialer: connect/update_state/mark_agent_call/disconnect).
    Jabvox::DialerAgentStateLogger.record(account_id: Current.account.id, user_id: current_user.id,
                                          state: params[:state].presence || 'inactive')
    ActionCable.server.broadcast("account_#{Current.account.id}",
                                 { event: 'jabvox.agent_state_changed', data: { account_id: Current.account.id } })
    render json: { ok: true }
  end

  # Reporte de ACTIVIDAD de Hermes: qué han hecho los agentes de Hermes sobre la cuenta,
  # a partir de la auditoría (JabvoxHermesActionLog). Solo lectura, scoped a la cuenta.
  # No requiere el módulo de IA activo para verse: es un reporte de operaciones.
  def hermes_activity
    date_range = build_date_range
    account_id = Current.account.id
    logs = JabvoxHermesActionLog.where(account_id: account_id, created_at: date_range)

    by_status = logs.reorder(nil).group(:status_jabvox).count
    total = by_status.values.sum
    by_tool = logs.reorder(nil).group(:tool_jabvox).count
                  .sort_by { |_tool, n| -n }
                  .map { |tool, n| { tool: tool, count: n } }
    by_identity = logs.reorder(nil).group(:hermes_identity_jabvox).count
                      .map { |identity, n| { identity: identity.presence || 'Manty', count: n } }

    # Serie diaria (para gráfica): fecha local → total de acciones ese día.
    per_day = logs.reorder(nil)
                  .group("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{report_time_zone}')")
                  .count
                  .sort_by { |day, _| day.to_s }
                  .map { |day, n| { date: day.to_s, count: n } }

    recent = logs.order(created_at: :desc).limit(20).map do |l|
      { id: l.id, created_at: l.created_at, tool: l.tool_jabvox, status: l.status_jabvox,
        identity: l.hermes_identity_jabvox, permission: l.permission_jabvox,
        duration_ms: l.duration_ms_jabvox, params: l.params_jabvox, error: l.error_jabvox }
    end

    render json: {
      fetched_at: Time.current.iso8601,
      totals: {
        total: total,
        success: by_status['success'] || 0,
        forbidden: by_status['forbidden'] || 0,
        module_disabled: by_status['module_disabled'] || 0,
        error: by_status['error'] || 0
      },
      by_tool: by_tool,
      by_identity: by_identity,
      per_day: per_day,
      recent: recent
    }
  end

  private

  # Zona horaria para agrupar por día. Usa la de la cuenta si está configurada.
  def report_time_zone
    tz = Current.account.timezone.presence || 'UTC'
    ActiveSupport::TimeZone[tz]&.tzinfo&.identifier || 'UTC'
  rescue StandardError
    'UTC'
  end

  # Estado del dialer EN VIVO desde Redis (la misma fuente que usa el propio
  # dialer: clave con TTL renovada por el heartbeat del agente). Antes se leía
  # account_users.jabvox_dialer_state, que nadie actualizaba => todos salían
  # "inactive" aunque estuvieran conectados.
  #   - sin clave (desconectado o TTL vencido)  => inactive
  #   - con in_call_contact_id                  => in_call
  #   - con state_id (pausa: comentarios, etc.) => paused (+ nombre del estado)
  #   - conectado sin pausa ni llamada          => waiting
  def dialer_live_state(user_id, pause_names, campaign_names)
    raw = Redis::Alfred.get("jabvox_dialer_agent_#{Current.account.id}_#{user_id}")
    state = raw ? JSON.parse(raw, symbolize_names: true) : nil
    return { state: 'inactive' } unless state

    since_epoch = state[:state_changed_at].presence || state[:connected_at].presence
    since = since_epoch ? Time.zone.at(since_epoch.to_i) : nil
    campaign = campaign_names[state[:campaign_id]]
    if state[:in_call_contact_id].present?
      { state: 'in_call', since: since, campaign: campaign }
    elsif state[:state_id].present?
      { state: 'paused', since: since, campaign: campaign,
        pause_name: pause_names[state[:state_id]] }
    else
      { state: 'waiting', since: since, campaign: campaign }
    end
  rescue StandardError
    { state: 'inactive' }
  end

  # Admins always pass (inside jabvox_can?); everyone else needs the
  # jabvox_reports_view permission from their custom role. Agents without a
  # custom role are denied — reports are opt-in per role.
  def ensure_reports_permission
    jabvox_authorize!('jabvox_reports_view')
  end

  def ensure_products_module
    return if Current.account.feature_enabled?('jabvox_products')

    render json: { error: 'Products module is not enabled for this account' }, status: :forbidden
  end

  def build_date_range
    from = params[:date_from].present? ? params[:date_from].to_date.beginning_of_day : 30.days.ago
    to_d = params[:date_to].present? ? params[:date_to].to_date.end_of_day : Time.current
    from..to_d
  end

  def build_dialer_state_times(account_id, date_range)
    range_start = date_range.begin.utc
    range_end   = date_range.end.utc
    conn = ApplicationRecord.connection
    qs = conn.quote(range_start.strftime('%Y-%m-%d %H:%M:%S'))
    qe = conn.quote(range_end.strftime('%Y-%m-%d %H:%M:%S'))

    rows = conn.select_all(<<~SQL)
      SELECT user_id,
             dialer_state AS state_key,
             GREATEST(
               SUM(EXTRACT(EPOCH FROM (
                 LEAST(COALESCE(ended_at, NOW()), #{qe}::timestamp) -
                 GREATEST(started_at, #{qs}::timestamp)
               )))::integer, 0
             ) AS seconds
      FROM jabvox_dialer_state_logs
      WHERE account_id = #{account_id.to_i}
        AND started_at < #{qe}::timestamp
        AND (ended_at IS NULL OR ended_at > #{qs}::timestamp)
      GROUP BY user_id, dialer_state
    SQL

    now = Time.current.utc
    result = {}
    rows.each do |row|
      uid = row['user_id']
      result[uid] ||= {}
      result[uid][row['state_key']] = row['seconds'].to_i
    end

    # Fallback: agents with no open dialer log entry — use jabvox_dialer_state_changed_at
    users_with_open = JabvoxDialerStateLog.where(account_id: account_id, ended_at: nil).pluck(:user_id).to_set
    cap_end = [range_end, now].min
    AccountUser.where(account_id: account_id).each do |au|
      next if users_with_open.include?(au.user_id) || au.jabvox_dialer_state_changed_at.nil?

      state_started = au.jabvox_dialer_state_changed_at.utc
      next if state_started >= cap_end

      sk  = au.jabvox_dialer_state.presence || 'inactive'
      eff = [state_started, range_start].max
      secs = [(cap_end - eff).to_i, 0].max

      result[au.user_id] ||= {}
      result[au.user_id][sk] = (result[au.user_id][sk] || 0) + secs
    end

    result
  end

  def build_dialer_current_states(account_id)
    result = {}
    JabvoxDialerStateLog.where(account_id: account_id, ended_at: nil).each do |log|
      result[log.user_id] = log.dialer_state
    end
    users_with_open = result.keys.to_set
    AccountUser.where(account_id: account_id).each do |au|
      next if users_with_open.include?(au.user_id) || au.jabvox_dialer_state_changed_at.nil?

      result[au.user_id] = au.jabvox_dialer_state.presence || 'inactive'
    end
    result
  end

  def build_current_states(account_id)
    result = {}
    JabvoxAppStateLog.where(account_id: account_id, ended_at: nil).each do |log|
      result[log.user_id] = log.app_state_id ? log.app_state_id.to_s : 'active'
    end
    users_with_open = result.keys.to_set
    AccountUser.where(account_id: account_id).each do |au|
      next if users_with_open.include?(au.user_id) || au.jabvox_app_state_changed_at.nil?

      result[au.user_id] = au.jabvox_app_state_id ? au.jabvox_app_state_id.to_s : 'active'
    end
    result
  end

  def build_state_times(account_id, date_range)
    range_start = date_range.begin.utc
    range_end = date_range.end.utc
    conn = ApplicationRecord.connection
    qs = conn.quote(range_start.strftime('%Y-%m-%d %H:%M:%S'))
    qe = conn.quote(range_end.strftime('%Y-%m-%d %H:%M:%S'))

    rows = conn.select_all(<<~SQL)
      SELECT user_id,
             COALESCE(app_state_id::text, 'active') AS state_key,
             GREATEST(
               SUM(EXTRACT(EPOCH FROM (
                 LEAST(COALESCE(ended_at, NOW()), #{qe}::timestamp) -
                 GREATEST(started_at, #{qs}::timestamp)
               )))::integer, 0
             ) AS seconds
      FROM jabvox_app_state_logs
      WHERE account_id = #{account_id.to_i}
        AND started_at < #{qe}::timestamp
        AND (ended_at IS NULL OR ended_at > #{qs}::timestamp)
      GROUP BY user_id, COALESCE(app_state_id::text, 'active')
    SQL

    now = Time.current.utc
    result = {}
    rows.each do |row|
      uid = row['user_id']
      result[uid] ||= {}
      result[uid][row['state_key']] = row['seconds'].to_i
    end

    # Fallback for agents who have a current state but no open log entry yet
    # (e.g. session started before state logging was deployed)
    users_with_open_log = JabvoxAppStateLog.where(account_id: account_id, ended_at: nil).pluck(:user_id).to_set
    cap_end = [range_end, now].min
    AccountUser.where(account_id: account_id).each do |au|
      next if users_with_open_log.include?(au.user_id)
      next if au.jabvox_app_state_changed_at.nil?

      state_started = au.jabvox_app_state_changed_at.utc
      next if state_started >= cap_end

      state_key = au.jabvox_app_state_id ? au.jabvox_app_state_id.to_s : 'active'
      effective_start = [state_started, range_start].max
      secs = [(cap_end - effective_start).to_i, 0].max

      result[au.user_id] ||= {}
      result[au.user_id][state_key] = (result[au.user_id][state_key] || 0) + secs
    end

    result
  end

  # Columns for the "time per app state" table. Starts from the configured
  # states (active ones first) and then appends any state key that shows up in
  # the computed times but is no longer configured (a deleted state with
  # historical logs) so its time is never silently hidden — the root cause of
  # "some agents show time and others don't".
  def build_state_columns(state_times)
    columns = [{ key: 'active', name: 'Activo', color: '#22c55e' }]
    configured = Current.account.jabvox_app_states.ordered
    configured.each { |s| columns << { key: s.id.to_s, name: s.name, color: s.color } }

    known_keys = columns.map { |c| c[:key] }.to_set
    used_keys = state_times.values.flat_map(&:keys).uniq
    used_keys.each do |key|
      next if known_keys.include?(key)

      columns << { key: key, name: "Estado eliminado (##{key})", color: '#94a3b8' }
    end
    columns
  end

  def serialize_order(order)
    contact = order.contact
    assignee = order.conversation&.assignee
    {
      id: order.id,
      # Se conserva la clave por compatibilidad con el frontend del reporte; ahora es el id
      # del contacto, el único identificador que queda tras retirar Leads.
      lead_id: order.contact_id,
      doc_type: order.doc_type,
      status: order.status,
      total: order.total.to_s,
      subtotal: order.subtotal.to_s,
      tax_total: order.tax_total.to_s,
      contact_id: contact&.id,
      contact_name: contact&.name,
      contact_phone: contact&.phone_number,
      assignee_id: assignee&.id,
      assignee_name: assignee&.name,
      conversation_id: order.conversation_id,
      created_at: order.created_at
    }
  end
end
