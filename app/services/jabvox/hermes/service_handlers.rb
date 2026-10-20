# frozen_string_literal: true

# Handlers de dominio de la capa de servicio de Hermes. Se separan de ServiceLayer (que solo
# enruta) para mantener el dispatch pequeño. Cada handler actúa SIEMPRE sobre @account (nunca
# un id enviado por el LLM) y NINGUNO borra: solo lee, crea y edita.
#
# Se incluye en Jabvox::Hermes::ServiceLayer, que provee @account, @user, MAX_ROWS y
# UnknownAction.
#
# Es intencionalmente largo: es el catálogo completo de acciones que Hermes puede ejecutar
# sobre la cuenta (una por área funcional). Cada handler es trivial; dividir el módulo solo
# fragmentaría la whitelist sin ganancia. Por eso se exime de ModuleLength.
# rubocop:disable Metrics/ModuleLength
module Jabvox::Hermes::ServiceHandlers
  # --- Handlers de dominio (account SIEMPRE = @account, nunca del LLM) ---

  # Etiquetas
  def list_labels(params)
    @account.labels.limit(capped_limit(params)).map { |l| { id: l.id, title: l.title, color: l.color } }
  end

  # show_on_sidebar has no DB default and defaults to false/nil, so a Label created
  # without it never shows in the sidebar's Etiquetas menu (Sidebar.vue's
  # getLabelsOnSidebar filters strictly on this column) — confirmed against production:
  # the label existed, had a color, and applied fine to conversations, but was invisible
  # in the menu. The web "Nueva etiqueta" form always sends true; match that here.
  def create_label(params)
    label = @account.labels.create!(title: params[:title], show_on_sidebar: true)
    { id: label.id, title: label.title }
  end

  def update_label(params)
    label = @account.labels.find(params[:id])
    attrs = { title: params[:title] }
    attrs[:show_on_sidebar] = params[:show_on_sidebar] unless params[:show_on_sidebar].nil?
    label.update!(attrs)
    { id: label.id, title: label.title, show_on_sidebar: label.show_on_sidebar }
  end

  # Bandejas (solo lectura)
  def list_inboxes(params)
    @account.inboxes.limit(capped_limit(params)).map { |i| { id: i.id, name: i.name, channel_type: i.channel_type } }
  end

  # Contactos
  def search_contacts(params)
    scope = @account.contacts
    q = params[:q].to_s.strip
    scope = scope.where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q', q: "%#{q}%") if q.present?
    scope.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |c| contact_view(c) }
  end

  def get_contact(params)
    contact_view(@account.contacts.find(params[:id]))
  end

  def create_contact(params)
    c = @account.contacts.create!(params.slice(:name, :email, :phone_number).compact_blank)
    contact_view(c)
  end

  def update_contact(params)
    c = @account.contacts.find(params[:id])
    c.update!(params.slice(:name, :email, :phone_number).compact_blank)
    contact_view(c)
  end

  # Conversaciones + mensajes
  # Métricas de conversaciones. Sin fechas da el total histórico de la cuenta; con
  # since/until acota el periodo, que es lo que permite responder "cuántas hubo el último
  # mes" o comparar un año contra otro. `inbox_id` acota a una bandeja.
  def conversations_meta(params)
    scope = @account.conversations
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].to_i.positive?
    scope = filter_by_date(scope, params, column: :last_activity_at)
    by_status = scope.group(:status).count
    messages = @account.messages.where(conversation_id: scope.select(:id))
    {
      total: by_status.values.sum, by_status: by_status,
      open: by_status['open'].to_i, resolved: by_status['resolved'].to_i,
      messages_total: messages.count,
      messages_incoming: messages.where(message_type: :incoming).count,
      messages_outgoing: messages.where(message_type: :outgoing).count,
      contacts_involved: scope.distinct.count(:contact_id),
      since: params[:since].presence, until: params[:until].presence
    }
  end

  # Resuelve una conversación por el DISPLAY_ID (el número visible por cuenta, que es el que
  # Hermes ve en el webhook y en las respuestas). Cae al id interno por compatibilidad. Así
  # get_conversation_messages/reply/etc. funcionan con el mismo número que Hermes conoce.
  def find_conversation(id)
    @account.conversations.find_by(display_id: id) ||
      @account.conversations.find_by(id: id) ||
      (raise ActiveRecord::RecordNotFound, "conversación #{id} no encontrada")
  end

  def list_conversation_messages(params)
    conv = find_conversation(params[:id])
    conv.messages.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |m|
      { id: m.id, content: m.content, message_type: m.message_type, private: m.private, created_at: m.created_at }
    end
  end

  # Lista conversaciones con filtros opcionales y paginación por cursor (before_id).
  def list_conversations(params)
    scope = @account.conversations.includes(:contact, :assignee)
    scope = scope.where(status: params[:status]) if params[:status].present? &&
                                                    Conversation.statuses.key?(params[:status])
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].to_i.positive?
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].to_i.positive?
    scope = scope.where('conversations.id < ?', params[:before_id]) if params[:before_id].to_i.positive?
    # Rango de fechas sobre la ÚLTIMA ACTIVIDAD, no la creación: "las conversaciones del
    # último mes" significa las que se movieron en ese periodo, no las que nacieron en él.
    scope = filter_by_date(scope, params, column: :last_activity_at)
    limit = params[:limit].to_i
    limit = 25 unless limit.positive?
    limit = [limit, Jabvox::Hermes::ServiceLayer::MAX_ROWS].min

    rows = scope.order(id: :desc).limit(limit).map do |c|
      { id: c.id, display_id: c.display_id, status: c.status, inbox_id: c.inbox_id,
        contact: c.contact && { id: c.contact.id, name: c.contact.name },
        assignee: c.assignee && { id: c.assignee.id, name: c.assignee.name },
        last_activity_at: c.last_activity_at, created_at: c.created_at }
    end
    { conversations: rows, next_before_id: rows.last&.dig(:id) }
  end

  # Tope de mensajes por conversación cuando se pide la ventana de historial (with_messages),
  # para que una conversación enorme no sature la respuesta del agente.
  MESSAGES_WINDOW_CAP = 30

  # Ventana de mensajes de UNA conversación para armar "el resumen de hoy": los mensajes del
  # rango efectivo (hoy por defecto, o since/until/last_*), sin notas privadas, orden cronológico,
  # topados a MESSAGES_WINDOW_CAP. Si no se pide rango, cae a los últimos del día de hoy.
  def conversation_messages_window(conv, params)
    from, to = effective_range(params)
    from ||= Time.current.beginning_of_day
    msgs = conv.messages.where(private: false).where.not(message_type: :activity)
    msgs = msgs.where('messages.created_at >= ?', from)
    msgs = msgs.where('messages.created_at <= ?', to) if to
    msgs.order(created_at: :asc).last(MESSAGES_WINDOW_CAP)
        .map { |m| { role: m.message_type, content: m.content, at: m.created_at } }
  end

  # Conversaciones SIN RESPONDER desde hace N tiempo: el cliente escribió y el agente aún no
  # contesta. Se apoya en la columna `waiting_since` que Message ya mantiene (se setea cuando
  # entra un mensaje del cliente y se limpia cuando el agente responde), así que es el instante
  # exacto desde el que la conversación lleva esperando respuesta.
  #
  # El umbral se pasa relativo (last_minutes/last_hours/last_days): "sin responder hace más de
  # 5 horas" => last_hours:5. Sin umbral, devuelve todas las que estén esperando respuesta.
  # Acota opcionalmente por bandeja (inbox_id). Incluye el texto del último mensaje del cliente;
  # con `with_messages=true` incluye además la ventana de mensajes de hoy (para el resumen).
  def unanswered_conversations(params)
    threshold = relative_threshold(params)
    with_messages = ActiveModel::Type::Boolean.new.cast(params[:with_messages])
    scope = @account.conversations.includes(:contact, :assignee).where.not(waiting_since: nil)
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].to_i.positive?
    scope = scope.where('conversations.waiting_since <= ?', threshold) if threshold
    limit = capped_limit(params, default: 25)

    rows = scope.order(waiting_since: :asc).limit(limit).map do |c|
      waiting_minutes = ((Time.current - c.waiting_since) / 60).round
      last_incoming = c.messages.where(message_type: :incoming, private: false).order(created_at: :desc).first
      row = { id: c.id, display_id: c.display_id, status: c.status, inbox_id: c.inbox_id,
              contact: c.contact && { id: c.contact.id, name: c.contact.name },
              assignee: c.assignee && { id: c.assignee.id, name: c.assignee.name },
              waiting_since: c.waiting_since, waiting_minutes: waiting_minutes,
              last_message: last_incoming && { content: last_incoming.content, at: last_incoming.created_at } }
      row[:messages] = conversation_messages_window(c, params) if with_messages
      row
    end
    { conversations: rows, count: rows.size, threshold: threshold }
  end

  # Últimas conversaciones que tuvieron actividad, CON el texto del último mensaje. Responde
  # directamente "los últimos N que escribieron y qué dijeron" en una sola llamada (list_conversations
  # no trae el texto y ordena por id, no por actividad). Orden por last_activity_at desc.
  # `incoming_only` (por defecto true) toma el último mensaje DEL CLIENTE; en false toma el último
  # mensaje cualquiera. `with_messages=true` añade la ventana de mensajes de hoy/del rango por
  # conversación (para "el resumen de hoy"). Acota por bandeja y por rango de fechas opcional.
  def recent_conversations_with_message(params)
    incoming_only = params.key?(:incoming_only) ? ActiveModel::Type::Boolean.new.cast(params[:incoming_only]) : true
    with_messages = ActiveModel::Type::Boolean.new.cast(params[:with_messages])
    scope = @account.conversations.includes(:contact, :assignee)
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].to_i.positive?
    scope = filter_by_effective_range(scope, params, column: :last_activity_at)
    limit = capped_limit(params, default: 10)

    rows = scope.order(last_activity_at: :desc).limit(limit).map do |c|
      msgs = c.messages.where(private: false)
      msgs = msgs.where(message_type: :incoming) if incoming_only
      last = msgs.order(created_at: :desc).first
      row = { id: c.id, display_id: c.display_id, status: c.status, inbox_id: c.inbox_id,
              contact: c.contact && { id: c.contact.id, name: c.contact.name },
              assignee: c.assignee && { id: c.assignee.id, name: c.assignee.name },
              last_activity_at: c.last_activity_at,
              last_message: last && { content: last.content, message_type: last.message_type, at: last.created_at } }
      row[:messages] = conversation_messages_window(c, params) if with_messages
      row
    end
    { conversations: rows, count: rows.size }
  end

  # Conteo de mensajes POR TIPO DE CONTENIDO: texto vs multimedia (audio/imagen/documento/vídeo).
  # El tipo multimedia NO vive en Message.content_type (que es texto/formularios), sino en los
  # ATTACHMENTS (file_type). Por eso se cuentan dos cosas: mensajes de texto (sin adjunto) y
  # adjuntos agrupados por su file_type. Acota por bandeja, por dirección (incoming/outgoing) y
  # por rango de fechas. Scoped a la cuenta.
  def messages_by_content_type(params)
    msg_scope = @account.messages
    msg_scope = msg_scope.joins(:conversation).where(conversations: { inbox_id: params[:inbox_id] }) if params[:inbox_id].to_i.positive?
    if params[:message_type].present? && Message.message_types.key?(params[:message_type])
      msg_scope = msg_scope.where(message_type: params[:message_type])
    end
    msg_scope = filter_by_date(msg_scope, params, column: :created_at)

    total = msg_scope.count
    # DISTINCT por id (no por la fila entera): messages tiene columnas json que PG no puede
    # comparar en un SELECT DISTINCT messages.*.
    with_attachments = msg_scope.joins(:attachments).distinct.count('messages.id')
    text_only = total - with_attachments
    # .group sobre un enum de Rails devuelve las claves como NOMBRE (string), no el entero.
    by_file_type = Attachment.where(message_id: msg_scope.select('messages.id')).group(:file_type).count

    {
      total: total,
      text_only: text_only,
      with_attachments: with_attachments,
      attachments_by_type: {
        audio: by_file_type['audio'].to_i,
        image: by_file_type['image'].to_i,
        video: by_file_type['video'].to_i,
        document: by_file_type['file'].to_i,
        other: by_file_type.reject { |k, _| %w[audio image video file].include?(k.to_s) }.values.sum
      },
      since: params[:since].presence, until: params[:until].presence
    }
  end

  # Rendimiento REAL por agente en un rango: por cada agente de la cuenta, mensajes salientes,
  # notas privadas, conversaciones asignadas y resueltas. El report_agents_summary existente
  # solo da agregados de cuenta; este desglosa por agente. Scoped a la cuenta. Todo agregado en
  # SQL (GROUP BY ... COUNT), no trae filas a Ruby: escala con muchas cuentas. Si se pasa
  # `agent_id`, limita el resultado a ese agente. Acota por rango de fechas.
  def agent_performance(params)
    agents = @account.users.order(:name)
    agents = agents.where(id: params[:agent_id].to_i) if params[:agent_id].to_i.positive?
    agents = agents.to_a

    # .reorder(nil): los scopes por defecto ordenan por created_at; en una consulta GROUP BY
    # agregada ese ORDER BY rompe en PG ("must appear in GROUP BY"). Se quita para agrupar.
    # El rango acepta tanto fechas absolutas (since/until) como relativas (last_days/hours/minutes).
    outgoing = @account.messages.where(message_type: :outgoing, sender_type: 'User').reorder(nil)
    outgoing = filter_by_effective_range(outgoing, params, column: :created_at)
    messages_by_sender = outgoing.where(private: false).group(:sender_id).count
    notes_by_sender = outgoing.where(private: true).group(:sender_id).count

    assigned_by_agent = @account.conversations.where.not(assignee_id: nil).reorder(nil).group(:assignee_id).count

    resolved_scope = @account.conversations.where(status: :resolved).where.not(assignee_id: nil).reorder(nil)
    resolved_scope = filter_by_effective_range(resolved_scope, params, column: :updated_at)
    resolved_by_agent = resolved_scope.group(:assignee_id).count

    rows = agents.map do |u|
      { agent_id: u.id, name: u.name,
        messages_sent: messages_by_sender[u.id].to_i,
        private_notes: notes_by_sender[u.id].to_i,
        conversations_assigned: assigned_by_agent[u.id].to_i,
        conversations_resolved: resolved_by_agent[u.id].to_i }
    end
    { agents: rows, agents_total: rows.size,
      since: params[:since].presence, until: params[:until].presence }
  end

  # Últimos mensajes escritos por UN agente concreto (los que envió, no los que recibió).
  # Responde "qué ha dicho el agente tal últimamente". Incluye a qué conversación pertenece
  # cada uno. `include_notes` (por defecto false) excluye notas privadas; en true las incluye.
  # Acota por bandeja y rango de fechas. Scoped a la cuenta. Topado a MAX_ROWS.
  def agent_messages(params)
    agent = @account.users.find(params[:agent_id])
    include_notes = ActiveModel::Type::Boolean.new.cast(params[:include_notes])
    scope = @account.messages.where(sender_type: 'User', sender_id: agent.id, message_type: :outgoing)
    scope = scope.where(private: false) unless include_notes
    scope = scope.joins(:conversation).where(conversations: { inbox_id: params[:inbox_id] }) if params[:inbox_id].to_i.positive?
    scope = filter_by_effective_range(scope, params, column: :created_at)
    limit = capped_limit(params, default: 20)

    rows = scope.reorder(created_at: :desc).limit(limit).map do |m|
      { id: m.id, conversation_id: m.conversation&.display_id, content: m.content,
        private: m.private, created_at: m.created_at }
    end
    { agent: { id: agent.id, name: agent.name }, messages: rows, count: rows.size }
  end

  # Tiempo que un agente ha estado conectado (estado de app), con duración real a partir del
  # histórico jabvox_app_state_logs (started_at/ended_at). Para "cuánto lleva/llevó conectado":
  # por defecto hoy (zona de la cuenta); con since/until, el rango dado. Suma los tramos cerrados
  # y, si hay un tramo abierto (ended_at nil), lo cuenta hasta ahora. También reporta el estado
  # actual online/offline (Redis). Scoped a cuenta+agente, usando el índice (account_id,user_id,started_at).
  def agent_online_time(params)
    agent = @account.users.find(params[:agent_id])
    # Acepta relativo (last_hours/days) o absoluto (since/until); sin nada, hoy.
    range_from, range_to = effective_range(params)
    from = range_from || Time.current.beginning_of_day
    to   = range_to || Time.current

    logs = JabvoxAppStateLog.where(account_id: @account.id, user_id: agent.id)
                            .where('started_at <= ?', to)
                            .where('ended_at IS NULL OR ended_at >= ?', from)
    total_seconds = logs.sum do |log|
      seg_start = [log.started_at, from].max
      seg_end   = [log.ended_at || Time.current, to].min
      [(seg_end - seg_start).to_i, 0].max
    end
    online_now = begin
      OnlineStatusTracker.get_available_users(@account.id).key?(agent.id.to_s) ||
        OnlineStatusTracker.get_available_users(@account.id).key?(agent.id)
    rescue StandardError
      nil
    end
    { agent: { id: agent.id, name: agent.name },
      connected_seconds: total_seconds,
      connected_minutes: (total_seconds / 60.0).round(1),
      connected_hours: (total_seconds / 3600.0).round(2),
      sessions: logs.size, online_now: online_now,
      since: from, until: to }
  end

  # Ventas (pedidos doc_type=SALE) con su agente (created_by) y su cliente, para "las últimas
  # ventas, a quién pertenecen". Por defecto solo ventas; doc_type='QUOTE' para cotizaciones, o
  # 'ALL' para ambas. Acota por agente, estado, rango de fechas. Scoped a cuenta. Topado a MAX_ROWS.
  # Incluye un agregado de total vendido para el periodo consultado.
  def sales_by_agent(params)
    doc = params[:doc_type].to_s.upcase
    scope = @account.jabvox_orders.includes(:contact)
    scope = scope.where(doc_type: if doc.presence == 'ALL'
                                    JabvoxOrder::DOC_TYPES
                                  else
                                    (JabvoxOrder::DOC_TYPES.include?(doc) ? doc : 'SALE')
                                  end)
    scope = scope.where(created_by_id: params[:agent_id].to_i) if params[:agent_id].to_i.positive?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = filter_by_effective_range(scope, params, column: :created_at)
    limit = capped_limit(params, default: 20)

    agent_names = @account.users.where(id: scope.distinct.pluck(:created_by_id).compact).pluck(:id, :name).to_h
    rows = scope.reorder(created_at: :desc).limit(limit).map do |o|
      { id: o.id, doc_type: o.doc_type, status: o.status, total: o.total,
        agent: o.created_by_id && { id: o.created_by_id, name: agent_names[o.created_by_id] },
        contact: o.contact && { id: o.contact.id, name: o.contact.name },
        created_at: o.created_at }
    end
    { orders: rows, count: rows.size,
      total_amount: scope.sum(:total),
      since: params[:since].presence, until: params[:until].presence }
  end

  # Métricas que admite la serie diaria.
  DAILY_METRICS = %w[messages messages_incoming messages_outgoing private_notes sales conversations_resolved].freeze

  # Serie POR DÍA de una métrica en un rango: "cuántos mensajes/ventas por día esta semana".
  # Agrupa en SQL por día (zona de la cuenta) — no trae filas a Ruby, escala. Rango por since/until
  # o relativo (last_days). Métrica elegible (`metric`), opcional por agente (agent_id) y bandeja.
  # Devuelve un mapa { "YYYY-MM-DD" => valor } con los días del rango.
  def daily_series(params)
    metric = DAILY_METRICS.include?(params[:metric].to_s) ? params[:metric].to_s : 'messages'
    since_at, until_at = effective_range(params)
    since_at ||= 7.days.ago.beginning_of_day
    until_at ||= Time.current
    # Account no tiene timezone propia (es por inbox). Se permite override por param y, si no,
    # se usa la zona por defecto de la app (configurada para Jabvox), cayendo a UTC.
    tzone = daily_series_timezone(params[:timezone])

    series =
      case metric
      when 'sales'
        sales_daily_series(params, since_at, until_at, tzone)
      when 'conversations_resolved'
        conversations_resolved_daily_series(params, since_at, until_at, tzone)
      else
        messages_daily_series(metric, params, since_at, until_at, tzone)
      end

    { metric: metric, timezone: tzone, by_day: series.transform_keys(&:to_s),
      total: series.values.sum, since: since_at, until: until_at }
  end

  # Material listo para que Hermes resuma: metadatos + últimos mensajes (sin notas
  # privadas). No llama al LLM — Hermes hace el resumen con este contexto.
  def summarize_conversation(params)
    conv = find_conversation(params[:id])
    messages = conv.messages.where(private: false).order(created_at: :asc)
                   .last(Jabvox::Hermes::ServiceLayer::MAX_ROWS)
                   .map { |m| { role: m.message_type, content: m.content, at: m.created_at } }
    {
      conversation_id: conv.id, display_id: conv.display_id, status: conv.status,
      contact: conv.contact && { id: conv.contact.id, name: conv.contact.name },
      assignee: conv.assignee&.name,
      labels: conv.cached_label_list,
      message_count: conv.messages.count,
      messages: messages
    }
  end

  def reply_conversation(params)
    conv = find_conversation(params[:id])
    msg = conv.messages.create!(
      account_id: @account.id, message_type: :outgoing, content: params[:content],
      # El AUTOR visible es el AgentBot "Hermes" (nombre propio, no un agente humano).
      # La autorización ya se resolvió antes con @user; aquí solo se marca la autoría.
      sender: hermes_sender, inbox_id: conv.inbox_id,
      additional_attributes: hermes_message_attrs
    )
    { id: msg.id, conversation_id: conv.display_id }
  end

  # Atributos que identifican un mensaje/nota como enviado por el agente Hermes.
  # Se mantienen por compatibilidad con el panel propio (JabvoxConversationHistory) y se
  # añade senderName (camelCase) que es el que lee el bubble estándar de Chatwoot.
  def hermes_message_attrs
    { 'sent_by_hermes' => true, 'hermes_agent_name' => HERMES_DISPLAY_NAME, 'senderName' => HERMES_DISPLAY_NAME }
  end

  # Nombre visible del agente IA en el CRM. Fijo "Hermes" (ignora el name_jabvox técnico
  # tipo "hermes_account_N"). Si en el futuro se quiere configurable, se cambia aquí.
  HERMES_DISPLAY_NAME = 'Hermes'

  # AgentBot "Hermes" de la cuenta (autor visible de las respuestas de la IA). Se crea una vez
  # por cuenta y se reutiliza; distingue inequívocamente a Hermes de los agentes humanos.
  def hermes_sender
    @hermes_sender ||= @account.agent_bots.find_or_create_by!(name: HERMES_DISPLAY_NAME) do |bot|
      bot.description = 'Agente IA (Hermes) de Jabvox'
    end
  end

  # Nota privada en una conversación (mensaje interno, no visible al cliente).
  def add_private_note(params)
    conv = find_conversation(params[:id])
    msg = conv.messages.create!(
      account_id: @account.id, message_type: :outgoing, content: params[:content],
      private: true, sender: hermes_sender, inbox_id: conv.inbox_id,
      additional_attributes: hermes_message_attrs
    )
    { id: msg.id, conversation_id: conv.display_id, private: true }
  end

  # Notas de contacto
  def list_contact_notes(params)
    contact = @account.contacts.find(params[:id])
    contact.notes.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |n| { id: n.id, content: n.content } }
  end

  def create_contact_note(params)
    contact = @account.contacts.find(params[:id])
    note = @account.notes.create!(contact: contact, user: @user, content: params[:content])
    { id: note.id, content: note.content }
  end

  # Automatizaciones
  def list_automation_rules(params)
    @account.automation_rules.limit(capped_limit(params)).map { |r| { id: r.id, name: r.name, active: r.active } }
  end

  def create_automation_rule(params)
    rule = @account.automation_rules.create!(
      name: params[:name], event_name: params[:event_name],
      conditions: Array(params[:conditions]), actions: Array(params[:actions]), active: true
    )
    { id: rule.id, name: rule.name, active: rule.active }
  end

  def update_automation_rule(params)
    rule = @account.automation_rules.find(params[:id])
    attrs = { name: params[:name], active: params[:active] }.compact
    attrs[:conditions] = Array(params[:conditions]) if params.key?(:conditions)
    attrs[:actions] = Array(params[:actions]) if params.key?(:actions)
    rule.update!(attrs)
    automation_rule_view(rule)
  end

  def get_automation_rule(params)
    automation_rule_view(@account.automation_rules.find(params[:id]), full: true)
  end

  # Activa o desactiva una automatización básica (active: true/false).
  def toggle_automation_rule(params)
    rule = @account.automation_rules.find(params[:id])
    active = params.key?(:active) ? !!params[:active] : !rule.active
    rule.update!(active: active)
    automation_rule_view(rule)
  end

  # Clona una automatización básica (misma lógica que AutomationRulesController#clone: dup + save).
  def clone_automation_rule(params)
    original = @account.automation_rules.find(params[:id])
    copy = original.dup
    copy.name = "#{original.name} (copia)"
    copy.save!
    automation_rule_view(copy)
  end

  def automation_rule_view(rule, full: false)
    base = { id: rule.id, name: rule.name, event_name: rule.event_name, active: rule.active }
    base.merge!(conditions: rule.conditions, actions: rule.actions, description: rule.description) if full
    base
  end

  # --- Integración por WEBHOOK directo al Hermes de la cuenta ---
  # Hermes se integra como un webhook (no como AgentBot de Jabvox). Jabvox dispara
  # message_created hacia el Hermes de la cuenta; el Hermes responde vía reply_conversation.

  def list_webhooks(params)
    @account.webhooks.limit(capped_limit(params)).map { |w| webhook_view(w) }
  end

  # Webhook Hermes para TODAS las bandejas (account_type). La URL la FIJA Jabvox al endpoint
  # de webhooks del Hermes de la cuenta. Idempotente por (account, url). Devuelve el SECRET y
  # las instrucciones de firma HMAC para que Hermes se AUTOCONFIGURE (solo el propio Hermes,
  # autenticado por su token, recibe este secret).
  def create_hermes_webhook(_params)
    hook = upsert_hermes_webhook(webhook_type: :account_type, inbox_id: nil)
    hermes_webhook_setup(hook)
  end

  # Webhook Hermes para UNA bandeja concreta (inbox_type). Chatwoot solo entregará los
  # message_created de ESA inbox → Hermes recibe solo esa bandeja. Devuelve secret + firma.
  def create_hermes_inbox_webhook(params)
    inbox = @account.inboxes.find(params[:inbox_id]) # scoped → no cross-account
    hook = upsert_hermes_webhook(webhook_type: :inbox_type, inbox_id: inbox.id)
    hermes_webhook_setup(hook).merge(inbox_id: inbox.id)
  end

  # Reglas de respuesta del webhook: define CUÁNDO responde Hermes. Solo normaliza las claves
  # conocidas (allowed_inbox_ids, excluded_labels, within_working_hours); ignora cualquier otra.
  # scoped a @account → no cross-account. No borra. Devuelve la vista segura del webhook.
  def update_webhook_conditions(params)
    hook = @account.webhooks.find(params[:id])
    raw = params[:conditions].is_a?(Hash) ? params[:conditions] : {}
    hook.update!(conditions: sanitize_webhook_conditions(raw))
    webhook_view(hook)
  end

  def sanitize_webhook_conditions(raw)
    {
      'allowed_inbox_ids' => Array(raw['allowed_inbox_ids'] || raw[:allowed_inbox_ids]).map(&:to_i).reject(&:zero?).uniq,
      'excluded_labels' => Array(raw['excluded_labels'] || raw[:excluded_labels]).map { |l| l.to_s.strip }.reject(&:blank?).uniq,
      'within_working_hours' => ActiveModel::Type::Boolean.new.cast(raw['within_working_hours'] || raw[:within_working_hours]) || false
    }
  end

  # Devuelve la configuración COMPLETA para que Hermes valide los webhooks entrantes de
  # Jabvox: URL, secret y el esquema de firma HMAC exacto. Con esto Hermes se aprovisiona
  # solo. El secret solo viaja a este Hermes (autenticado por su token) — nunca se registra
  # en la auditoría (JabvoxHermesActionLog sanea claves 'secret').
  def hermes_webhook_setup(hook)
    {
      id: hook.id, url: hook.url, webhook_type: hook.webhook_type, subscriptions: hook.subscriptions,
      secret: hook.secret,
      signature: {
        algorithm: 'HMAC-SHA256',
        signed_payload: '{timestamp}.{raw_body}',
        # Jabvox envía la MISMA firma en dos juegos de headers para máxima compatibilidad:
        jabvox_headers: { signature: 'X-Jabvox-Signature (formato "sha256=<hex>")',
                          timestamp: 'X-Jabvox-Timestamp', delivery: 'X-Jabvox-Delivery' },
        # Formato V2 genérico (el que reconocen los gateways tipo Hermes): hex crudo.
        webhook_v2_headers: { signature: 'X-Webhook-Signature-V2 (hex crudo, sin prefijo)',
                              timestamp: 'X-Webhook-Timestamp' },
        timestamp_window_seconds: 300,
        instructions: 'Valida: hmac = HMAC_SHA256(secret, "{X-Webhook-Timestamp}.{cuerpo_crudo}"). ' \
                      'Compara ese hex con X-Webhook-Signature-V2 (o "sha256="+hex con X-Jabvox-Signature). ' \
                      'Configura tu plataforma webhook con este secret y el esquema V2 (no uses INSECURE_NO_AUTH).'
      }
    }
  end

  # Crea/actualiza el webhook al Hermes de la cuenta suscrito a message_created.
  def upsert_hermes_webhook(webhook_type:, inbox_id:)
    hook = @account.webhooks.find_or_initialize_by(url: hermes_webhook_url)
    hook.webhook_type = webhook_type
    hook.inbox_id = inbox_id
    hook.subscriptions = %w[message_created]
    hook.save!
    hook
  end

  # URL del endpoint de WEBHOOKS de Hermes (distinto del chat). Deriva del hermes_url del
  # handoff: reemplaza el chat (.../v1) por el endpoint de webhooks del agente. Puerto y ruta
  # configurables por ENV para tu setup (por defecto :8644 y /webhooks/jabvox).
  def hermes_webhook_url
    base = hermes_outgoing_url! # http://host:8642/p/<agente>/v1
    prefix = base.sub(%r{/v1/?\z}, '') # http://host:8642/p/<agente>
    port = ENV['HERMES_WEBHOOK_PORT'].presence || '8644'
    path = ENV['HERMES_WEBHOOK_PATH'].presence || 'webhooks/jabvox'
    prefix.sub(/:\d+/, ":#{port}") + "/#{path}"
  end

  # Gestiones (management states)
  def list_management_states(params)
    @account.jabvox_management_states.limit(capped_limit(params))
            .map { |s| { id: s.id, name: s.name_jabvox, color: s.color_jabvox } }
  end

  def create_management_state(params)
    s = @account.jabvox_management_states.create!(name_jabvox: params[:name])
    { id: s.id, name: s.name_jabvox }
  end

  def update_management_state(params)
    s = @account.jabvox_management_states.find(params[:id])
    s.update!(name_jabvox: params[:name])
    { id: s.id, name: s.name_jabvox }
  end

  # Dialer
  def list_dialer_campaigns(params)
    @account.jabvox_dialer_campaigns.limit(capped_limit(params))
            .map { |c| { id: c.id, name: c.name_jabvox, status: c.status_jabvox } }
  end

  def get_dialer_campaign(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    { id: c.id, name: c.name_jabvox, status: c.status_jabvox }
  end

  def create_dialer_campaign(params)
    c = @account.jabvox_dialer_campaigns.create!(name_jabvox: params[:name])
    { id: c.id, name: c.name_jabvox, status: c.status_jabvox }
  end

  def update_dialer_campaign(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    c.update!(name_jabvox: params[:name])
    { id: c.id, name: c.name_jabvox, status: c.status_jabvox }
  end

  # Masivos (SMS)
  def list_sms_campaigns(params)
    scope = filter_by_date(@account.jabvox_sms_campaigns, params)
    scope.limit(capped_limit(params)).map { |c| sms_view(c) }
  end

  def create_sms_campaign(params)
    c = @account.jabvox_sms_campaigns.create!(name: params[:name], message: params[:message])
    sms_view(c)
  end

  def update_sms_campaign(params)
    c = @account.jabvox_sms_campaigns.find(params[:id])
    c.update!({ name: params[:name], message: params[:message] }.compact)
    sms_view(c)
  end

  # Reportes: resumen de la cuenta (solo lectura, conteos vía ActiveRecord, nunca SQL directo).
  def report_agents_summary(_params)
    {
      conversations_open: @account.conversations.open.count,
      conversations_total: @account.conversations.count,
      contacts_total: @account.contacts.count,
      agents_total: @account.account_users.count,
      labels_total: @account.labels.count
    }
  end

  # --- helpers ---

  # URL del Hermes de ESTA cuenta (destino de bots/webhooks). Nunca una URL del LLM.
  def hermes_outgoing_url!
    url = @account.jabvox_context_forge_handoff&.hermes_url
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'la cuenta no tiene un Hermes conectado (sin hermes_url)' if url.blank?

    url
  end

  # --- vistas seguras ---

  def webhook_view(hook)
    { id: hook.id, url: hook.url, webhook_type: hook.webhook_type, subscriptions: hook.subscriptions,
      inbox_id: hook.inbox_id, conditions: hook.conditions }
  end

  def sms_view(campaign)
    { id: campaign.id, name: campaign.try(:name), message: campaign.try(:message) }
  end

  def contact_view(contact)
    { id: contact.id, name: contact.name, email: contact.email, phone_number: contact.phone_number }
  end

  # --- Análisis de Audio (solo lectura) ---
  def list_audio_jobs(params)
    scope = filter_by_date(@account.jabvox_audio_jobs, params)
    scope.order(created_at: :desc).limit(capped_limit(params)).map do |j|
      { id: j.id, status: j.status, total: j.total_count, processed: j.processed_count,
        passed: j.passed_count, failed: j.failed_count, created_at: j.created_at }
    end
  end

  def get_audio_job(params)
    j = @account.jabvox_audio_jobs.find(params[:id])
    { id: j.id, status: j.status, total: j.total_count, processed: j.processed_count,
      passed: j.passed_count, failed: j.failed_count, error_count: j.error_count,
      pipeline_id: j.pipeline_id, created_at: j.created_at }
  end

  def list_audio_pipelines(params)
    @account.jabvox_audio_pipelines.order(:id).limit(capped_limit(params)).map do |p|
      { id: p.id, name: p.try(:name_jabvox) || p.try(:name) }
    end
  end

  # --- Analytics / BD externas (solo lectura; sin credenciales) ---
  def list_analytics_data_sources(params)
    @account.jabvox_analytics_data_sources.order(:id).limit(capped_limit(params)).map do |d|
      { id: d.id, name: d.name_jabvox, engine: d.engine_jabvox, database: d.database_jabvox }
    end
  end

  def list_analytics_dashboards(params)
    @account.jabvox_analytics_dashboards.order(:id).limit(capped_limit(params)).map do |d|
      { id: d.id, name: d.try(:name_jabvox) || d.try(:name) }
    end
  end

  # --- Pedidos (solo lectura) ---
  def list_orders(params)
    scope = @account.jabvox_orders.order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(doc_type: params[:doc_type]) if params[:doc_type].present?
    scope.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |o|
      { id: o.id, doc_type: o.doc_type, status: o.status, total: o.total.to_s,
        contact_id: o.contact_id, created_at: o.created_at }
    end
  end

  # --- Tareas (solo lectura) ---
  # Tareas de un tablero/columna/responsable. Sin filtros devuelve las más recientes de toda
  # la cuenta; con `board_id` solo las de ese tablero (antes traía todas, daba igual lo que
  # se pidiera). Incluye el nombre de la columna y del responsable para que el agente pueda
  # responder "en qué estado está" y "quién la tiene" sin una segunda consulta.
  def list_tasks(params)
    scope = @account.jabvox_tasks.includes(:stage, :assignee)
    scope = filter_by(scope, params, :board_id, :stage_id, :assignee_id)
    scope = filter_by_date(scope, params)
    scope.order(created_at: :desc).limit(capped_limit(params)).map { |t| task_view(t) }
  end

  # --- Calendario (solo lectura) ---
  # El título de una cita suele llevar el nombre del cliente, así que de las ajenas solo
  # se devuelve la franja ocupada: la misma regla que aplica la API REST. Sin esto, pedirle
  # la agenda a Jabvox IA esquivaba la protección del calendario.
  def list_calendar_events(params)
    scope = filter_by_date(@account.jabvox_calendar_events, params, column: :start_at)
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present?
    scope.order(start_at: :desc).limit(capped_limit(params))
         .includes(:jabvox_calendar_event_participants).map do |e|
      title = calendar_policy(e).full_detail? ? e.title : I18n.t('jabvox.calendar.busy', default: 'Ocupado')
      { id: e.id, title: title, start_at: e.start_at, end_at: e.end_at }
    end
  end

  # === Analytics / BD externas ===
  def get_analytics_data_source(params)
    d = @account.jabvox_analytics_data_sources.find(params[:id])
    { id: d.id, name: d.name_jabvox, engine: d.engine_jabvox, database: d.database_jabvox,
      host: d.host_jabvox, has_password: d.respond_to?(:password_jabvox) }
  end

  def analytics_data_source_schema(params)
    d = @account.jabvox_analytics_data_sources.find(params[:id])
    Jabvox::Analytics::IntrospectionService.new(d).call
  rescue StandardError => e
    { error: e.message }
  end

  # Ejecuta SQL read-only contra la BD externa usando las credenciales GUARDADAS
  # en la data_source (Hermes nunca las recibe). Validado read-only por el servicio.
  def run_analytics_query(params)
    d = @account.jabvox_analytics_data_sources.find(params[:id])
    outcome = Jabvox::Analytics::QueryExecutionService.new(data_source: d, user: @user)
                                                      .run_custom_sql(params[:sql].to_s)
    outcome.to_h
  rescue Jabvox::Analytics::QueryExecutionService::RejectedError => e
    # SQL rechazado por no ser de solo lectura.
    { rejected: true, error: e.message }
  rescue Jabvox::Analytics::Adapters::BaseAdapter::ConnectionError => e
    # No se pudo conectar a la BD externa (credenciales/host); el mensaje es
    # accionable para que Hermes lo traslade al usuario. Nunca expone credenciales.
    { connection_error: true, error: "No se pudo conectar a la base de datos externa: #{e.message}" }
  end

  def preview_analytics_table(params)
    d = @account.jabvox_analytics_data_sources.find(params[:id])
    Jabvox::Analytics::QueryExecutionService.new(data_source: d, user: @user)
                                            .preview(table: params[:table], page: params[:page] || 1,
                                                     per_page: [params[:per_page].to_i, 100].reject(&:zero?).min || 25)
                                            .to_h
  end

  # === Carpetas de Analytics ===
  def list_analytics_folders(params)
    @account.jabvox_analytics_folders.order(:id).limit(capped_limit(params)).map do |f|
      { id: f.id, name: f.try(:name_jabvox) || f.try(:name) }
    end
  end

  def create_analytics_folder(params)
    f = @account.jabvox_analytics_folders.create!(name_jabvox: params[:name].to_s)
    { id: f.id, name: f.name_jabvox }
  end

  def update_analytics_folder(params)
    f = @account.jabvox_analytics_folders.find(params[:id])
    f.update!(name_jabvox: params[:name].to_s)
    { id: f.id, name: f.name_jabvox }
  end

  # === Reportes cruzados (join entre varias BD externas) ===
  def list_analytics_cross_reports(params)
    JabvoxAnalyticsCrossReport.where(account_id: @account.id).order(:id)
                              .limit(capped_limit(params))
                              .map { |r| { id: r.id, name: r.try(:name_jabvox) || r.try(:name) } }
  end

  def get_analytics_cross_report(params)
    r = JabvoxAnalyticsCrossReport.find_by!(id: params[:id], account_id: @account.id)
    { id: r.id, name: r.try(:name_jabvox) || r.try(:name) }
  end

  # Ejecuta un reporte cruzado guardado (read-only). Reusa el servicio de la UI.
  def execute_analytics_cross_report(params)
    r = JabvoxAnalyticsCrossReport.find_by!(id: params[:id], account_id: @account.id)
    result = Jabvox::Analytics::CrossReportExecutionService.new(r).call
    { columns: result.columns, rows: Array(result.rows).first(Jabvox::Hermes::ServiceLayer::MAX_ROWS),
      row_count: result.row_count }
  rescue Jabvox::Analytics::CrossReportExecutionService::ExecutionError => e
    { error: e.message }
  end

  def analytics_overview_stats(_params)
    { dashboards: @account.jabvox_analytics_dashboards.count,
      data_sources: @account.jabvox_analytics_data_sources.count,
      folders: @account.jabvox_analytics_folders.count }
  end

  def analytics_internal_reports(_params)
    return [] unless defined?(Jabvox::Analytics::InternalReportCatalog)

    Jabvox::Analytics::InternalReportCatalog.try(:all)&.map do |k|
      { key: k.is_a?(Hash) ? k[:key] : k }
    end || []
  rescue StandardError
    []
  end

  # === Reportes de la cuenta (solo lectura, resumen para Hermes) ===
  def report_products(params)
    scope = @account.jabvox_orders
    scope = apply_report_dates(scope, params, 'jabvox_orders')
    { total_orders: scope.count, total_amount: scope.sum(:total).to_s,
      by_status: scope.reorder(nil).group(:status).count,
      by_doc_type: scope.reorder(nil).group(:doc_type).count }
  end

  def report_dialer(params)
    scope = JabvoxDialerCallLog.where(account_id: @account.id)
    scope = apply_report_dates(scope, params, 'jabvox_dialer_call_logs')
    { total_calls: scope.count,
      answered: scope.where(status_jabvox: 'answered').count,
      total_duration_seconds: scope.sum(:duration_jabvox).to_i,
      by_status: scope.reorder(nil).group(:status_jabvox).count }
  end

  def report_agent_status(_params)
    online = begin
      OnlineStatusTracker.get_available_users(@account.id).keys
    rescue StandardError
      []
    end
    { online_agents: online.size,
      agents: @account.users.order(:name).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |u|
        { id: u.id, name: u.name, online: online.map(&:to_s).include?(u.id.to_s) }
      end }
  end

  def report_hermes_activity(params)
    scope = JabvoxHermesActionLog.where(account_id: @account.id)
    scope = apply_report_dates(scope, params, 'jabvox_hermes_action_logs')
    { total_actions: scope.count,
      by_status: scope.reorder(nil).group(:status_jabvox).count,
      by_tool: scope.reorder(nil).group(:tool_jabvox).order('count_all DESC').limit(20).count }
  end

  # === Dashboards / widgets (crear y gestionar) ===
  # Todo scoped a @account vía ActiveRecord. Hermes NUNCA maneja credenciales:
  # solo referencia data sources YA conectadas por su id.
  def get_analytics_dashboard(params)
    d = @account.jabvox_analytics_dashboards.find(params[:id])
    serialize_dashboard(d, with_widgets: true)
  end

  def create_analytics_dashboard(params)
    d = @account.jabvox_analytics_dashboards.new(
      name_jabvox: params[:name].to_s,
      description_jabvox: params[:description],
      folder_id: analytics_folder_id(params[:folder_id]),
      created_by: @user
    )
    d.save!
    serialize_dashboard(d)
  end

  def update_analytics_dashboard(params)
    d = @account.jabvox_analytics_dashboards.find(params[:id])
    attrs = {}
    attrs[:name_jabvox] = params[:name].to_s if params.key?(:name)
    attrs[:description_jabvox] = params[:description] if params.key?(:description)
    attrs[:folder_id] = analytics_folder_id(params[:folder_id]) if params.key?(:folder_id)
    d.update!(attrs)
    serialize_dashboard(d)
  end

  # Añade un widget a un dashboard. El data_source debe existir en ESTA cuenta;
  # si no, se rechaza (no se puede apuntar a una fuente de otra cuenta).
  def create_analytics_widget(params)
    dashboard = @account.jabvox_analytics_dashboards.find(params[:dashboard_id])
    data_source_id = resolve_widget_data_source_id(params[:data_source_id])
    widget = dashboard.widgets.new(
      account: @account,
      title_jabvox: params[:title].to_s,
      widget_type_jabvox: params[:widget_type].to_s.presence || 'table',
      data_source_id: data_source_id,
      custom_sql_jabvox: params[:custom_sql],
      query_spec_jabvox: params[:query_spec].is_a?(Hash) ? params[:query_spec] : {},
      config_jabvox: params[:config].is_a?(Hash) ? params[:config] : {}
    )
    widget.save!
    serialize_widget(widget)
  end

  def update_analytics_widget(params)
    dashboard = @account.jabvox_analytics_dashboards.find(params[:dashboard_id])
    widget = dashboard.widgets.find(params[:id])
    widget.update!(widget_update_attrs(params))
    serialize_widget(widget)
  end

  # Ejecuta un widget guardado (read-only). Reusa el mismo servicio que la UI:
  # custom_sql pasa por el validador read-only; el query visual por el builder.
  def execute_analytics_widget(params)
    dashboard = @account.jabvox_analytics_dashboards.find(params[:dashboard_id])
    widget = dashboard.widgets.find(params[:id])
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'el widget no tiene fuente de datos' if widget.data_source.blank?

    svc = Jabvox::Analytics::QueryExecutionService.new(
      data_source: widget.data_source, user: @user, ttl_seconds: dashboard.cache_ttl_seconds_jabvox
    )
    outcome = if widget.uses_custom_sql?
                svc.run_custom_sql(widget.custom_sql_jabvox)
              else
                svc.run_visual(widget.query_spec_jabvox)
              end
    outcome.to_h
  rescue Jabvox::Analytics::QueryExecutionService::RejectedError => e
    { rejected: true, error: e.message }
  rescue Jabvox::Analytics::Adapters::BaseAdapter::ConnectionError => e
    { connection_error: true, error: "No se pudo conectar a la base de datos externa: #{e.message}" }
  end

  # === Importar leads (pull desde BD externa) ===
  def list_lead_import_sources(params)
    @account.jabvox_lead_sources.order(:id).limit(capped_limit(params)).map do |s|
      { id: s.id, name: s.try(:name_jabvox), engine: s.try(:engine_jabvox), table: s.try(:table_jabvox) }
    end
  end

  def get_lead_import_source(params)
    s = @account.jabvox_lead_sources.find(params[:id])
    { id: s.id, name: s.try(:name_jabvox), engine: s.try(:engine_jabvox), table: s.try(:table_jabvox),
      last_sync: s.try(:last_sync_at_jabvox) }
  end

  def trigger_lead_import_sync(params)
    s = @account.jabvox_lead_sources.find(params[:id])
    Jabvox::LeadImport::SyncJob.perform_later(s.id)
    { queued: true, source_id: s.id }
  end

  def lead_import_sync_status(params)
    s = @account.jabvox_lead_sources.find(params[:id])
    { id: s.id, status: s.try(:sync_status_jabvox), last_sync: s.try(:last_sync_at_jabvox) }
  end

  # === Exportar datos ===
  def list_data_export_targets(params)
    @account.jabvox_export_targets.order(:id).limit(capped_limit(params)).map do |t|
      { id: t.id, name: t.try(:name_jabvox), engine: t.try(:engine_jabvox), enabled: t.try(:enabled_jabvox) }
    end
  end

  def get_data_export_target(params)
    t = @account.jabvox_export_targets.find(params[:id])
    { id: t.id, name: t.try(:name_jabvox), engine: t.try(:engine_jabvox), enabled: t.try(:enabled_jabvox),
      modules: t.try(:selected_modules_jabvox) }
  end

  def trigger_data_export_sync(params)
    t = @account.jabvox_export_targets.find(params[:id])
    Jabvox::ExternalExport::BackfillJob.perform_later(t.id)
    { queued: true, target_id: t.id }
  end

  # === Pedidos / productos ===
  def get_order(params)
    o = @account.jabvox_orders.includes(:jabvox_order_items).find(params[:id])
    { id: o.id, doc_type: o.doc_type, status: o.status, total: o.total.to_s,
      items: o.jabvox_order_items.map { |i| { name: i.name_snapshot, qty: i.quantity, total: i.line_total.to_s } } }
  end

  def list_products(params)
    @account.jabvox_products.order(:name_jabvox).limit(capped_limit(params)).map do |p|
      { id: p.id, name: p.name_jabvox, price: p.try(:price_jabvox)&.to_s, type: p.try(:product_type_jabvox) }
    end
  end

  def get_product(params)
    p = @account.jabvox_products.find(params[:id])
    { id: p.id, name: p.name_jabvox, price: p.try(:price_jabvox)&.to_s }
  end

  # === Módulos varios (solo lectura) ===
  # Tableros de tareas. Con `id` devuelve SOLO ese tablero (el agente preguntaba por uno y
  # recibía todos). Incluye sus columnas para que pueda razonar sobre el flujo sin otra
  # llamada, y el conteo de tareas por columna.
  def list_task_boards(params)
    scope = @account.jabvox_task_boards.includes(:stages)
    scope = scope.where(id: params[:id]) if params[:id].present?
    scope.order(:id).limit(capped_limit(params)).map do |b|
      { id: b.id, name: b.try(:name_jabvox) || b.try(:name), stages: board_stages(b) }
    end
  end

  def board_stages(board)
    stages = board.try(:stages)
    return [] if stages.blank?

    counts = @account.jabvox_tasks.where(board_id: board.id).group(:stage_id).count
    stages.map do |s|
      { id: s.id, name: s.try(:name_jabvox) || s.try(:name), tasks_count: counts[s.id].to_i }
    end
  end

  def list_tickets(params)
    scope = filter_by_date(@account.jabvox_tickets, params)
    scope.order(created_at: :desc).limit(capped_limit(params)).map do |t|
      { id: t.id, title: t.title_jabvox, status: t.status_jabvox, priority: t.priority_jabvox,
        created_at: t.created_at }
    end
  end

  def get_ticket(params)
    t = @account.jabvox_tickets.find(params[:id])
    { id: t.id, title: t.title_jabvox, status: t.status_jabvox, priority: t.priority_jabvox,
      description: t.description_jabvox, category_id: t.ticket_category_id }
  end

  def list_kanban_funnels(params)
    @account.jabvox_kanban_funnels.order(:id).limit(capped_limit(params)).map do |f|
      { id: f.id, name: f.try(:name_jabvox) || f.try(:name) }
    end
  end

  def list_flows(params)
    @account.jabvox_flows.order(:id).limit(capped_limit(params)).map { |f| flow_view(f) }
  end

  def get_flow(params)
    flow_view(@account.jabvox_flows.find(params[:id]))
  end

  def create_flow(params)
    f = @account.jabvox_flows.create!(params.slice(:name, :description, :folder_id).compact_blank)
    flow_view(f)
  end

  def update_flow(params)
    f = @account.jabvox_flows.find(params[:id])
    f.update!(params.slice(:name, :description, :folder_id).compact)
    flow_view(f)
  end

  # Cambia el estado del flujo. Activar (status:active) EXIGE que el grafo pase la
  # validación estricta, igual que el editor: no se deja activo un flujo que fallaría.
  def set_flow_status(params)
    f = @account.jabvox_flows.find(params[:id])
    status = params[:status].to_s
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, "estado no válido: #{status}" unless JabvoxFlow.statuses.key?(status)

    if status == 'active'
      graph = f.current_version&.graph || {}
      result = validate_flow_graph(graph)
      if result.respond_to?(:blocking?) && result.blocking?
        return { activated: false, error: 'El flujo tiene problemas y no se puede activar.',
                 validation: flow_validation_view(result) }
      end
    end
    f.update!(status: status)
    flow_view(f)
  end

  def duplicate_flow(params)
    original = @account.jabvox_flows.find(params[:id])
    copy = @account.jabvox_flows.create!(name: "#{original.name} (copia)", description: original.description,
                                         folder_id: original.folder_id, status: 'draft')
    if original.current_version&.graph.present? && copy.respond_to?(:versions)
      copy.versions.create!(graph: original.current_version.graph, version: 1, creator: @user)
    end
    flow_view(copy.reload)
  rescue StandardError
    flow_view(@account.jabvox_flows.find(params[:id])) # si el versionado difiere, al menos devuelve algo
  end

  # Valida el grafo del flujo (no lo activa): devuelve la lista de problemas.
  def validate_flow(params)
    f = @account.jabvox_flows.find(params[:id])
    graph = f.current_version&.graph || {}
    { flow_id: f.id, validation: flow_validation_view(validate_flow_graph(graph)) }
  end

  def run_flow(params)
    f = @account.jabvox_flows.find(params[:id])
    version = f.current_version
    return { queued: false, error: 'El flujo no tiene un grafo guardado todavía.' } if version.nil?

    Jabvox::Flows::RunJob.perform_later(f.id) if defined?(Jabvox::Flows::RunJob)
    { queued: true, flow_id: f.id, status: f.status }
  end

  # Catálogo de tipos de nodo (para que Hermes sepa qué puede construir y con qué params).
  def get_flow_node_types(_params)
    reg = Jabvox::Flows::Registry.build
    reg.types.map do |type|
      d = begin
        reg.definition(type)
      rescue StandardError
        nil
      end
      { type: type, label: (d.respond_to?(:label) ? d.label : reg.try(:label, type)),
        params: node_params_spec(reg, type) }
    end
  end

  # Guarda el grafo (nodos + conexiones) validándolo antes, igual que #save_version del
  # controller. En modo estricto rechaza si hay problemas bloqueantes.
  def save_flow_graph(params)
    f = @account.jabvox_flows.find(params[:id])
    graph = { 'nodes' => Array(params[:nodes]), 'edges' => Array(params[:edges]), 'notes' => Array(params[:notes]) }.as_json
    result = validate_flow_graph(graph)
    if result.respond_to?(:blocking?) && result.blocking? && params[:strict]
      return { saved: false, error: 'El flujo tiene problemas que impiden guardarlo.', validation: flow_validation_view(result) }
    end

    version = save_flow_version!(f, graph)
    { saved: true, flow_id: f.id, version: version.version, validation: flow_validation_view(result) }
  end

  # Prueba un nodo aislado (mismo servicio que el controller: TestNodeService). No activa nada.
  def test_flow_node(params)
    f = @account.jabvox_flows.find(params[:id])
    version = f.current_version
    return { error: 'El flujo no tiene un grafo guardado todavía.' } if version.nil?

    node_id = params[:node_id].to_s
    return { error: 'el nodo no existe en el grafo del flujo' } unless flow_node_in_graph?(version, node_id)

    Jabvox::Flows::TestNodeService.new(
      flow: f, version: version, node_id: node_id, user: @user,
      context: { payload: {}, prior_outputs: Hash(params[:prior_outputs]), use_last_run_context: false }
    ).call
  end

  # --- helpers de nodos de flujo ---
  def node_params_spec(reg, type)
    if reg.respond_to?(:params_spec)
      begin
        reg.params_spec(type)
      rescue StandardError
        nil
      end
    end
  rescue StandardError
    nil
  end

  def save_flow_version!(flow, graph)
    flow.with_lock do
      next_number = (flow.versions.maximum(:version) || 0) + 1
      version = flow.versions.create!(version: next_number, graph: graph, created_by: @user.id)
      flow.update!(current_version: version)
      version
    end
  end

  def flow_node_in_graph?(version, node_id)
    Array(version.graph&.dig('nodes')).any? { |n| (n['id'] || n[:id]).to_s == node_id }
  end

  # --- helpers de flujos ---
  def flow_view(f)
    { id: f.id, name: f.name, description: f.description, status: f.status, folder_id: f.folder_id,
      active: f.respond_to?(:active?) ? f.active? : (f.status == 'active') }
  end

  def validate_flow_graph(graph)
    return nil unless defined?(Jabvox::Flows::Validation::GraphValidator)

    Jabvox::Flows::Validation::GraphValidator.call(graph, mode: :strict, registry: Jabvox::Flows::Registry.build)
  rescue StandardError
    nil
  end

  def flow_validation_view(result)
    return { ok: true } if result.nil?

    issues = Array(result.try(:issues) || result.try(:errors)).map do |i|
      # Cada issue puede ser un struct/objeto; extraemos su mensaje legible.
      i.try(:message) || i.try(:to_h)&.slice(:message, :node_id, :severity) || i.to_s
    end
    { blocking: result.try(:blocking?), issues: issues }
  end

  def list_bulk_whatsapp_batches(params)
    scope = filter_by_date(@account.jabvox_bulk_whatsapp_batches, params)
    scope.order(created_at: :desc).limit(capped_limit(params)).map do |b|
      { id: b.id, status: b.try(:status_jabvox), total: b.try(:total_rows_jabvox),
        sent: b.try(:sent_count_jabvox), created_at: b.created_at }
    end
  end

  def list_whatsapp_templates(params)
    @account.jabvox_whatsapp_templates.order(:id).limit(capped_limit(params)).map { |t| whatsapp_template_view(t) }
  end

  # Reutiliza el mismo manager que el controller (Jabvox::WhatsappTemplatesManager), que
  # habla con Meta/proveedor y valida. Hermes nunca toca credenciales del canal.
  def create_whatsapp_template(params)
    inbox = @account.inboxes.find(params[:inbox_id])
    attrs = params.slice(:name, :category, :language, :inbox_id, :header_type, :header_content, :body, :footer).compact_blank
    attrs[:buttons] = Array(params[:buttons]) if params.key?(:buttons)
    result = whatsapp_templates_manager.create(inbox, attrs)
    return { error: result[:error] } unless result[:success]

    whatsapp_template_view(result[:template])
  end

  def update_whatsapp_template(params)
    t = @account.jabvox_whatsapp_templates.find(params[:id])
    attrs = params.slice(:name, :category, :language, :header_type, :header_content, :body, :footer).compact
    attrs[:buttons] = Array(params[:buttons]) if params.key?(:buttons)
    result = whatsapp_templates_manager.update(t, attrs)
    return { error: result[:error] } unless result[:success]

    whatsapp_template_view(result[:template])
  end

  def duplicate_whatsapp_template(params)
    t = @account.jabvox_whatsapp_templates.find(params[:id])
    result = whatsapp_templates_manager.duplicate(t, new_name: nil)
    return { error: result[:error] } unless result[:success]

    whatsapp_template_view(result[:template])
  end

  def sync_whatsapp_template(params)
    t = @account.jabvox_whatsapp_templates.find(params[:id])
    result = whatsapp_templates_manager.sync_single(t)
    return { error: result[:error] } unless result[:success]

    whatsapp_template_view(result[:template])
  end

  def reuse_bulk_whatsapp_batch(params)
    batch = @account.jabvox_bulk_whatsapp_batches.find(params[:id])
    # 'reuse' clona la configuración del lote como base para un reenvío.
    new_batch = batch.respond_to?(:reuse!) ? batch.reuse!(user: @user) : batch.dup.tap(&:save!)
    { id: new_batch.id, status: new_batch.try(:status_jabvox), reused_from: batch.id }
  end

  def get_bulk_whatsapp_batch(params)
    b = @account.jabvox_bulk_whatsapp_batches.find(params[:id])
    { id: b.id, status: b.try(:status_jabvox), total: b.try(:total_rows_jabvox),
      sent: b.try(:sent_count_jabvox), created_at: b.created_at }
  end

  # Crea y lanza un envío masivo a leads. Acción DISRUPTIVA (envía mensajes reales).
  # Reusa el mismo servicio que la UI (BulkWhatsappDispatchService). El sender debe
  # ser el propio usuario del agente salvo que sea admin (misma regla del controller).
  def create_bulk_whatsapp_batch(params)
    inbox = @account.inboxes.find(params[:inbox_id])
    sender = @account.users.find(params[:sender_user_id] || @user.id)
    unless admin_account_user? || sender.id == @user.id
      raise Jabvox::Hermes::ServiceLayer::Forbidden, 'solo un administrador puede enviar en nombre de otro usuario'
    end

    batch = Jabvox::BulkWhatsappDispatchService.prepare(
      account: @account, inbox: inbox, sender_user: sender, actor: @user,
      response_email: params[:response_email], template_name: params[:template_name],
      language: params[:language], text: params[:text],
      variable_map: params[:variable_map].is_a?(Hash) ? params[:variable_map] : {},
      leads_selection: bulk_leads_selection(params)
    )
    { id: batch.id, status: batch.try(:status_jabvox), total: batch.try(:total_rows_jabvox) }
  rescue Jabvox::BulkWhatsappDispatchService::Error => e
    { error: e.message }
  end

  # === Grupos de WhatsApp ===
  def list_whatsapp_groups(params)
    @account.jabvox_whatsapp_groups.order(:id).limit(capped_limit(params)).map { |g| whatsapp_group_view(g) }
  end

  def get_whatsapp_group(params)
    whatsapp_group_view(@account.jabvox_whatsapp_groups.find(params[:id]), members: true)
  end

  def create_whatsapp_group(params)
    inbox = @account.inboxes.find(params[:inbox_id])
    group = Jabvox::Whatsapp::GroupManager.new(inbox).create(
      name: params[:name].to_s, description: params[:description],
      created_by: @user, member_phones: Array(params[:member_phones])
    )
    whatsapp_group_view(group, members: true)
  end

  def update_whatsapp_group(params)
    group = @account.jabvox_whatsapp_groups.find(params[:id])
    Jabvox::Whatsapp::GroupManager.new(group.inbox).update_metadata(
      group, { name: params[:name], description: params[:description] }.compact
    )
    whatsapp_group_view(group.reload)
  end

  def add_whatsapp_group_member(params)
    group = @account.jabvox_whatsapp_groups.find(params[:id])
    Jabvox::Whatsapp::GroupManager.new(group.inbox).add_member(group, params[:phone].to_s)
    whatsapp_group_view(group.reload, members: true)
  end

  def send_whatsapp_group_message(params)
    group = @account.jabvox_whatsapp_groups.find(params[:id])
    Jabvox::Whatsapp::GroupManager.new(group.inbox).send_message(group, params[:text].to_s)
    { sent: true, group_id: group.id }
  end

  # === Voice Broadcast (gestión de campañas; el backend hace la marcación real) ===
  def list_voice_broadcasts(params)
    scope = filter_by_date(JabvoxVoiceBroadcast.for_account(@account.id).ordered, params)
    scope.limit(capped_limit(params)).map { |b| voice_broadcast_view(b) }
  end

  def get_voice_broadcast(params)
    voice_broadcast_view(find_voice_broadcast(params[:id]), detail: true)
  end

  def get_voice_broadcast_report(params)
    b = find_voice_broadcast(params[:id])
    { id: b.id, name: b.name_jabvox, status: b.status_jabvox,
      total_recipients: b.try(:total_recipients_jabvox), dialed: b.try(:dialed_count_jabvox),
      answered_human: b.try(:answered_human_count_jabvox), answered_machine: b.try(:answered_machine_count_jabvox),
      played_complete: b.try(:played_complete_count_jabvox), failed: b.try(:failed_count_jabvox) }
  end

  def create_voice_broadcast(params)
    b = JabvoxVoiceBroadcast.new(voice_broadcast_attrs(params))
    b.account = @account
    b.created_by = @user
    b.source_jabvox = 'leads'
    b.save!
    voice_broadcast_view(b, detail: true)
  end

  def update_voice_broadcast(params)
    b = find_voice_broadcast(params[:id])
    b.update!(voice_broadcast_attrs(params))
    voice_broadcast_view(b, detail: true)
  end

  # Cambia el estado. start EXIGE audio listo (falla limpio si no lo hay); el backend
  # (TickAccountJob) hace la marcación. Hermes nunca toca AMI ni origina llamadas.
  def start_voice_broadcast(params)
    b = find_voice_broadcast(params[:id])
    return { error: 'Sube y despliega el audio de la campaña primero (desde la interfaz).' } unless b.audio_ready?

    b.update!(status_jabvox: 'running', started_at_jabvox: b.started_at_jabvox || Time.current)
    Jabvox::VoiceBroadcast::TickAccountJob.perform_later(b.id)
    voice_broadcast_view(b, detail: true)
  end

  def pause_voice_broadcast(params)
    b = find_voice_broadcast(params[:id])
    b.update!(status_jabvox: 'paused') if b.running?
    voice_broadcast_view(b, detail: true)
  end

  def resume_voice_broadcast(params)
    b = find_voice_broadcast(params[:id])
    return { error: 'Solo se puede reanudar una campaña pausada.' } unless b.status_jabvox == 'paused'

    b.update!(status_jabvox: 'running')
    Jabvox::VoiceBroadcast::TickAccountJob.perform_later(b.id)
    voice_broadcast_view(b, detail: true)
  end

  def stop_voice_broadcast(params)
    b = find_voice_broadcast(params[:id])
    b.update!(status_jabvox: 'stopped', finished_at_jabvox: Time.current)
    voice_broadcast_view(b, detail: true)
  end

  # Envía una plantilla de WhatsApp APROBADA a un contacto. Crea/reusa su conversación en la
  # bandeja WhatsApp y despacha la plantilla (el canal la manda a Meta). Requiere que la
  # plantilla esté aprobada por Meta y que el contacto tenga teléfono.
  def send_whatsapp_template_to_contact(params)
    template = @account.jabvox_whatsapp_templates.find(params[:template_id])
    contact = @account.contacts.find(params[:contact_id])
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'el contacto no tiene teléfono' if contact.phone_number.blank?

    status = template.try(:status_jabvox) || template.try(:status)
    unless status.to_s.upcase == 'APPROVED'
      return { sent: false, status: status,
               error: "la plantilla no está aprobada por Meta (estado: #{status}). No se puede enviar hasta que Meta la apruebe." }
    end

    inbox = template.try(:inbox) || @account.inboxes.find_by(id: template.try(:inbox_id))
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'la plantilla no tiene bandeja de WhatsApp asociada' if inbox.nil?

    conversation = whatsapp_conversation_for(contact, inbox)
    tmpl_params = { 'name' => (template.try(:name_jabvox) || template.try(:name)),
                    'category' => template.try(:category), 'language' => template.try(:language) }
    msg = conversation.messages.create!(
      account_id: @account.id, inbox_id: inbox.id, message_type: :outgoing,
      content: template.try(:body) || template.try(:name_jabvox).to_s, sender: hermes_sender,
      additional_attributes: { 'template_params' => tmpl_params.compact }.merge(hermes_message_attrs)
    )
    SendReplyJob.perform_later(msg.id)
    { sent: true, message_id: msg.id, conversation_id: conversation.display_id, contact_id: contact.id }
  end

  # Conversación abierta del contacto en esa bandeja WhatsApp, o una nueva.
  def whatsapp_conversation_for(contact, inbox)
    ci = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) do |c|
      c.source_id = contact.phone_number.to_s.delete('+')
    end
    ci.conversations.where(status: %i[open pending]).order(created_at: :desc).first ||
      @account.conversations.create!(contact: contact, inbox: inbox, contact_inbox: ci)
  end

  def whatsapp_templates_manager
    @whatsapp_templates_manager ||= Jabvox::WhatsappTemplatesManager.new(@account, user: @user)
  end

  def whatsapp_template_view(t)
    { id: t.id, name: t.try(:name_jabvox) || t.try(:name), category: t.try(:category),
      language: t.try(:language), status: t.try(:status_jabvox) || t.try(:status), inbox_id: t.try(:inbox_id) }
  end

  def list_affiliates(params)
    @account.jabvox_affiliates.order(:id).limit(capped_limit(params)).map do |a|
      { id: a.id, name: a.try(:name_jabvox) || a.try(:name) }
    end
  end

  def list_campaigns(params)
    @account.jabvox_campaigns.order(:id).limit(capped_limit(params)).map do |c|
      { id: c.id, name: c.try(:name_jabvox) || c.try(:name) }
    end
  end

  # Registros de llamadas. `calldate` es datetime naive del PBX, así que el rango se compara
  # sobre esa misma columna (no created_at) para que "el último mes" signifique la fecha de
  # la llamada y no la de ingesta.
  def list_cdr_records(params)
    scope = JabvoxCdrRecord.where(account_id: @account.id)
    scope = filter_by(scope, params, :disposition, :src, :dst)
    scope = filter_by_date(scope, params, column: :calldate)
    scope.order(calldate: :desc).limit(capped_limit(params)).map do |r|
      { id: r.id, src: r.src, dst: r.dst, disposition: r.disposition, duration: r.duration, calldate: r.calldate }
    end
  end

  def list_custom_tables(params)
    @account.jabvox_custom_tables.order(:id).limit(capped_limit(params)).map do |t|
      { id: t.id, name: t.try(:name_jabvox), kind: t.try(:kind_jabvox), linked_to: t.try(:linked_to_jabvox) }
    end
  end

  # ==========================================================================
  # LOTE "TODO ES TODO" — handlers de escritura por módulo (nunca borran).
  # ==========================================================================

  # --- Comunicación: bandeja API + conversaciones ---
  def create_api_inbox(params)
    channel = @account.api_channels.create!(webhook_url: params[:webhook_url].presence)
    inbox = @account.inboxes.create!(name: params[:name].to_s.presence || 'Hermes API', channel: channel)
    { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type }
  end

  def update_conversation_status(params)
    conv = find_conversation(params[:id])
    status = params[:status].to_s
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, "estado no válido: #{status}" unless Conversation.statuses.key?(status)

    conv.status = status
    conv.snoozed_until = parse_snoozed_until(params[:snoozed_until]) if status == 'snoozed' && params[:snoozed_until].present?
    conv.save!
    { id: conv.id, display_id: conv.display_id, status: conv.status }
  end

  def assign_conversation(params)
    conv = find_conversation(params[:id])
    if params[:assignee_id].to_i.positive?
      agent = @account.users.find(params[:assignee_id])
      Conversations::AssignmentService.new(conversation: conv, assignee_id: agent.id).perform
    elsif params[:team_id].to_i.positive?
      conv.update!(team: @account.teams.find(params[:team_id]))
    else
      raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'indica assignee_id o team_id'
    end
    conv.reload
    { id: conv.id, display_id: conv.display_id,
      assignee: conv.assignee && { id: conv.assignee.id, name: conv.assignee.name },
      team: conv.team && { id: conv.team.id, name: conv.team.name } }
  end

  def parse_snoozed_until(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # --- Plantillas de correo ---
  def list_email_templates(params)
    scope = filter_by_date(@account.jabvox_email_templates, params)
    scope.order(created_at: :desc).limit(capped_limit(params)).map { |t| email_template_view(t) }
  end

  def create_email_template(params)
    email_template_view(@account.jabvox_email_templates.create!(params.slice(:name, :subject, :body, :active).compact_blank))
  end

  def update_email_template(params)
    t = @account.jabvox_email_templates.find(params[:id])
    t.update!(params.slice(:name, :subject, :body, :active).compact)
    email_template_view(t)
  end

  def test_send_email_template(params)
    t = @account.jabvox_email_templates.find(params[:id])
    config = @account.jabvox_smtp_config
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'la cuenta no tiene SMTP configurado' if config&.address.blank?

    to = params[:to].to_s.strip
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'indica el correo destino (to)' if to.blank?

    Jabvox::EmailSenderService.new(account: @account, config: config, to: to,
                                   subject: t.subject.to_s, html_body: t.body.to_s, source: 'manual', user: @user).deliver!
    { sent: true, template_id: t.id, to: to }
  end

  def send_email_template_to_contact(params)
    t = @account.jabvox_email_templates.find(params[:id])
    config = @account.jabvox_smtp_config
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'la cuenta no tiene SMTP configurado' if config&.address.blank?

    contact = @account.contacts.find(params[:contact_id])
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'el contacto no tiene correo' if contact.email.blank?

    Jabvox::EmailSenderService.new(account: @account, config: config, to: contact.email,
                                   subject: interpolate_email(t.subject.to_s, contact),
                                   html_body: interpolate_email(t.body.to_s, contact), source: 'manual', user: @user).deliver!
    { sent: true, template_id: t.id, contact_id: contact.id }
  end

  def email_template_view(template)
    { id: template.id, name: template.name, subject: template.subject, active: template.active }
  end

  def interpolate_email(text, contact)
    text.gsub('{{contact_name}}', contact.name.to_s)
        .gsub('{{contact_email}}', contact.email.to_s)
        .gsub('{{contact_phone}}', contact.phone_number.to_s)
  end

  # --- Formularios ---
  def list_forms(params)
    @account.jabvox_forms.order(:id).limit(capped_limit(params)).map { |f| form_view(f) }
  end

  def get_form(params)
    form_view(@account.jabvox_forms.find(params[:id]), full: true)
  end

  def create_form(params)
    form_view(@account.jabvox_forms.create!(form_attrs(params)), full: true)
  end

  def update_form(params)
    f = @account.jabvox_forms.find(params[:id])
    f.update!(form_attrs(params))
    form_view(f, full: true)
  end

  def form_attrs(params)
    attrs = params.slice(:name_jabvox, :slug_jabvox, :submit_button_text_jabvox, :active_jabvox).compact_blank
    attrs[:fields_jabvox] = Array(params[:fields_jabvox]) if params.key?(:fields_jabvox)
    attrs
  end

  def form_view(form, full: false)
    base = { id: form.id, name_jabvox: form.name_jabvox, slug_jabvox: form.slug_jabvox, active_jabvox: form.active_jabvox }
    base[:fields_jabvox] = form.fields_jabvox if full
    base
  end

  # --- Tareas ---
  def create_task(params)
    attrs = params.slice(:title_jabvox, :board_id, :stage_id, :jabvox_lead_id, :assignee_id,
                         :description_jabvox, :priority_jabvox, :status_jabvox, :due_at_jabvox).compact_blank
    # Normaliza enums a valores válidos (evita fallos por 'medium'/'media' u otros):
    # priority ∈ low/normal/high/urgent (default normal); status ∈ open/done (default open).
    attrs[:priority_jabvox] = normalize_task_priority(attrs[:priority_jabvox])
    attrs[:status_jabvox] = %w[open done].include?(attrs[:status_jabvox].to_s) ? attrs[:status_jabvox] : 'open'
    # board/stage son obligatorios: si no vienen, usa el primer board/etapa de la cuenta.
    attrs[:board_id] ||= @account.jabvox_task_boards.order(:id).first&.id
    attrs[:stage_id] ||= @account.jabvox_task_stages.where(board_id: attrs[:board_id]).order(:position_jabvox).first&.id
    t = @account.jabvox_tasks.new(attrs)
    t.created_by = @user
    t.save!
    task_view(t)
  end

  def normalize_task_priority(value)
    v = value.to_s.downcase
    return v if %w[low normal high urgent].include?(v)

    { 'media' => 'normal', 'medium' => 'normal', 'baja' => 'low', 'alta' => 'high',
      'urgente' => 'urgent' }.fetch(v, 'normal')
  end

  def update_task(params)
    t = @account.jabvox_tasks.find(params[:id])
    t.update!(params.slice(:title_jabvox, :stage_id, :assignee_id, :description_jabvox,
                           :priority_jabvox, :status_jabvox, :due_at_jabvox).compact_blank)
    task_view(t)
  end

  def move_task(params)
    t = @account.jabvox_tasks.find(params[:id])
    stage = @account.jabvox_task_stages.find(params[:stage_id])
    t.update!(stage_id: stage.id, position_jabvox: params[:position].to_i)
    task_view(t)
  end

  # Incluye los NOMBRES de columna y responsable, no solo los ids: el agente necesita poder
  # decir "está en Pendiente, asignada a Ana" sin encadenar dos consultas más.
  def task_view(task)
    { id: task.id, title: task.title_jabvox, board_id: task.board_id, stage_id: task.stage_id,
      stage_name: task.try(:stage)&.name_jabvox,
      assignee_id: task.assignee_id, assignee_name: task.try(:assignee)&.name,
      priority: task.priority_jabvox, status: task.status_jabvox, due_at: task.due_at_jabvox }
  end

  def create_task_board(params)
    b = @account.jabvox_task_boards.new(params.slice(:name_jabvox, :description_jabvox, :position_jabvox, :is_active_jabvox).compact_blank)
    b.created_by = @user
    b.save!
    { id: b.id, name: b.name_jabvox, is_active: b.is_active_jabvox }
  end

  def update_task_board(params)
    b = @account.jabvox_task_boards.find(params[:id])
    b.update!(params.slice(:name_jabvox, :description_jabvox, :position_jabvox, :is_active_jabvox).compact_blank)
    { id: b.id, name: b.name_jabvox, is_active: b.is_active_jabvox }
  end

  def create_task_stage(params)
    board = @account.jabvox_task_boards.find(params[:board_id])
    s = board.stages.new(params.slice(:name_jabvox, :color_jabvox, :position_jabvox).compact_blank)
    s.account = @account
    s.save!
    { id: s.id, board_id: s.board_id, name: s.name_jabvox, color: s.color_jabvox }
  end

  def update_task_stage(params)
    s = @account.jabvox_task_stages.find(params[:id])
    s.update!(params.slice(:name_jabvox, :color_jabvox, :position_jabvox).compact_blank)
    { id: s.id, board_id: s.board_id, name: s.name_jabvox, color: s.color_jabvox }
  end

  # --- Calendario ---
  def create_calendar_event(params)
    attrs = params.slice(:title, :description, :note, :all_day, :event_type, :status, :color,
                         :contact_id, :branch_id).compact_blank
    events = Jabvox::CalendarEventBuilder.new(
      account: @account, user: @user, attributes: attrs,
      slots: [{ start_at: params[:start_at], end_at: params[:end_at], all_day: params[:all_day] }], participants: []
    ).perform!
    Array(events).map { |e| calendar_event_view(e) }
  rescue StandardError => e
    # El builder puede fallar DESPUÉS de crear el evento (p.ej. al notificar/enviar
    # recordatorio). Si el evento quedó creado, lo devolvemos igual en vez de reportar error.
    created = @account.jabvox_calendar_events.where(title: attrs[:title]).order(created_at: :desc).first
    raise e if created.nil? || (Time.current - created.created_at) > 30

    [calendar_event_view(created)]
  end

  # Modificar la cita de otro se rechaza igual que por la API: el agente solo toca lo que
  # organiza o donde participa.
  def update_calendar_event(params)
    e = @account.jabvox_calendar_events.find(params[:id])
    raise Jabvox::Hermes::ServiceLayer::Forbidden, 'no puedes modificar esta cita' unless calendar_policy(e).manage?

    e.update!(params.slice(:title, :description, :note, :event_type, :status, :color,
                           :contact_id, :branch_id).compact_blank)
    calendar_event_view(e)
  end

  def calendar_policy(event)
    Jabvox::CalendarEventPolicy.new(event, @account.account_users.find_by(user_id: @user&.id))
  end

  def calendar_event_view(e)
    { id: e.id, title: e.title, start_at: e.start_at, end_at: e.end_at, all_day: e.all_day,
      event_type: e.event_type, status: e.status, contact_id: e.contact_id,
      branch_id: e.branch_id, branch_name: e.branch&.name_jabvox }
  end

  # Sedes de la cuenta con su horario: Hermes las necesita para saber dónde agendar y a
  # qué horas abre cada una. Solo lectura — crearlas es cosa del administrador.
  def get_calendar_branches(_params = {})
    @account.jabvox_branches.active.ordered.includes(:hours).map do |b|
      { id: b.id, name: b.name_jabvox, timezone: b.timezone_jabvox,
        hours: b.hours.order(:day_of_week, :open_minute).map do |h|
          { day_of_week: h.day_of_week, open_minute: h.open_minute, close_minute: h.close_minute }
        end }
    end
  end

  def create_calendar_external_person(params)
    p = @account.jabvox_calendar_external_people.create!(params.slice(:name, :email, :phone_number, :notes, :color).compact_blank)
    external_person_view(p)
  end

  def update_calendar_external_person(params)
    p = @account.jabvox_calendar_external_people.find(params[:id])
    p.update!(params.slice(:name, :email, :phone_number, :notes, :color).compact_blank)
    external_person_view(p)
  end

  def external_person_view(p)
    { id: p.id, name: p.name, email: p.email, phone_number: p.phone_number, color: p.color }
  end

  # --- Chat interno de equipo ---
  def list_internal_chats(params)
    scope = filter_by_date(internal_chat_scope, params, column: :updated_at)
    scope.order(updated_at: :desc).limit(capped_limit(params)).map { |c| internal_chat_view(c) }
  end

  def create_internal_chat(params)
    chat = params[:chat_type].to_s == 'group_chat' ? create_internal_group(params) : find_or_create_internal_direct(params)
    internal_chat_view(chat)
  end

  def send_internal_chat_message(params)
    chat = internal_chat_scope.find(params[:id])
    content = params[:content].to_s.strip
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'content requerido' if content.blank?

    msg = chat.messages.create!(sender: @user, content: content)
    Jabvox::InternalChatPushJob.perform_later(msg.id)
    { id: msg.id, chat_id: chat.id, content: msg.content, created_at: msg.created_at }
  end

  def mark_internal_chat_read(params)
    chat = internal_chat_scope.find(params[:id])
    chat.members.find_by(user_id: @user.id)&.update!(unread_count: 0, last_read_at: Time.current)
    { ok: true, chat_id: chat.id }
  end

  def internal_chat_scope
    JabvoxInternalChat.for_user(@user.id).where(account: @account)
  end

  def create_internal_group(params)
    chat = JabvoxInternalChat.create!(account: @account, created_by: @user, chat_type: :group_chat, name: params[:name].to_s.strip)
    ((Array(params[:member_ids]).map(&:to_i)) + [@user.id]).uniq.each { |uid| chat.members.create!(user_id: uid) if @account.users.exists?(uid) }
    chat
  end

  def find_or_create_internal_direct(params)
    other_id = params[:user_id].to_i
    mine = JabvoxInternalChatMember.where(user_id: @user.id).select(:chat_id)
    existing = JabvoxInternalChat.where(account: @account, chat_type: :direct, id: mine).joins(:members)
                                 .where(jabvox_internal_chat_members: { user_id: other_id }).first
    return existing if existing

    chat = JabvoxInternalChat.create!(account: @account, created_by: @user, chat_type: :direct)
    chat.members.create!(user_id: @user.id)
    chat.members.create!(user_id: other_id) if @account.users.exists?(other_id)
    chat
  end

  def internal_chat_view(chat)
    { id: chat.id, chat_type: chat.chat_type, name: chat.try(:name), members: chat.users.map { |u| { id: u.id, name: u.name } } }
  end

  # --- Kanban ---
  def create_kanban_funnel(params)
    f = @account.jabvox_kanban_funnels.create!(params.slice(:name_jabvox, :description_jabvox, :position_jabvox,
                                                            :active_jabvox, :include_own_contacts_jabvox).compact_blank)
    kanban_funnel_view(f)
  end

  def update_kanban_funnel(params)
    f = @account.jabvox_kanban_funnels.find(params[:id])
    f.update!(params.slice(:name_jabvox, :description_jabvox, :position_jabvox, :active_jabvox, :include_own_contacts_jabvox).compact_blank)
    kanban_funnel_view(f)
  end

  def kanban_funnel_view(f)
    { id: f.id, name: f.name_jabvox, active: f.active_jabvox, position: f.position_jabvox }
  end

  def create_kanban_stage(params)
    funnel = @account.jabvox_kanban_funnels.find(params[:kanban_funnel_id])
    s = funnel.jabvox_kanban_stages.create!(params.slice(:name_jabvox, :description_jabvox, :color_jabvox, :position_jabvox).compact_blank
                                                  .merge(account_id: @account.id))
    kanban_stage_view(s)
  end

  def update_kanban_stage(params)
    s = @account.jabvox_kanban_stages.find(params[:id])
    s.update!(params.slice(:name_jabvox, :description_jabvox, :color_jabvox, :position_jabvox).compact_blank)
    kanban_stage_view(s)
  end

  def kanban_stage_view(s)
    { id: s.id, funnel_id: s.jabvox_kanban_funnel_id, name: s.name_jabvox, color: s.color_jabvox, position: s.position_jabvox }
  end

  # --- Gestiones: export con preguntas ---
  def export_management_states(_params)
    @account.jabvox_management_states.includes(:questions).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |s|
      { id: s.id, name: s.name_jabvox, color: s.try(:color_jabvox), is_active: s.try(:is_active_jabvox),
        questions: s.questions.map { |q| { label: q.try(:label), type: q.try(:question_type), required: q.try(:required) } } }
    end
  end

  # --- Dialer ---
  def start_dialer_campaign(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    c.update!(status_jabvox: 'active')
    { id: c.id, name: c.name_jabvox, status: c.status_jabvox }
  end

  def pause_dialer_campaign(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    c.update!(status_jabvox: 'paused')
    { id: c.id, name: c.name_jabvox, status: c.status_jabvox }
  end

  def stop_dialer_campaign(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    c.update!(status_jabvox: 'completed')
    { id: c.id, name: c.name_jabvox, status: c.status_jabvox }
  end

  def retry_dialer_campaign(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    c.update!(status_jabvox: 'active') unless c.status_jabvox == 'active'
    { id: c.id, name: c.name_jabvox, status: c.status_jabvox }
  end

  # NO-DESTRUCTIVO: en vez de borrar la fila (como hace la UI), la RESETEA a 'pending'
  # con attempts=0 para que el motor la vuelva a marcar. Hermes nunca borra registros.
  def redial_dialer_lead(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    cc = c.jabvox_dialer_campaign_contacts.find_by(contact_id: params[:contact_id].to_i)
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'contacto no encontrado en la campaña' unless cc

    cc.update!(status_jabvox: 'pending', attempts_jabvox: 0, last_attempt_at_jabvox: nil)
    { ok: true, campaign_id: c.id, contact_id: params[:contact_id].to_i, status: cc.status_jabvox }
  end

  # NO-DESTRUCTIVO: añade el contacto a la lista de exclusión (el motor ya no lo marca) y
  # cierra la fila pendiente marcándola 'completed' en vez de borrarla. Hermes nunca borra.
  #
  # La lista guarda ids de CONTACTO: es lo que compara el filtro del marcador. Antes este
  # handler traducía el contacto a su lead, que era un rodeo innecesario incluso entonces.
  def exclude_dialer_lead(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    contact = @account.contacts.find_by(id: params[:contact_id].to_i)
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'contacto no encontrado' unless contact

    add_contact_to_exclusion(c, contact.id)
    cc = c.jabvox_dialer_campaign_contacts.find_by(contact_id: contact.id)
    cc.update!(status_jabvox: 'completed') if cc && cc.status_jabvox == 'pending'
    { ok: true, campaign_id: c.id, contact_id: contact.id }
  end

  # Añade un contacto a la lista de exclusión de la campaña (idempotente).
  def add_contact_to_exclusion(campaign, contact_id)
    excluded = Array(campaign.excluded_lead_ids_jabvox).map(&:to_i)
    excluded << contact_id unless excluded.include?(contact_id)
    campaign.update!(excluded_lead_ids_jabvox: excluded.uniq)
  end

  def import_dialer_contacts(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    rows = Array(params[:contacts]).map do |ct|
      ct = ct.respond_to?(:to_h) ? ct.to_h.symbolize_keys : ct
      { account_id: @account.id, jabvox_dialer_campaign_id: c.id, name_jabvox: ct[:name].to_s,
        phone_jabvox: ct[:phone].to_s.strip, status_jabvox: 'pending', attempts_jabvox: 0 }
    end.select { |r| r[:phone_jabvox].present? }
    JabvoxDialerCampaignContact.insert_all!(rows) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    { imported: rows.size, campaign_id: c.id }
  end

  def dialer_campaign_progress(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    ccs = c.jabvox_dialer_campaign_contacts
    { campaign_id: c.id, status: c.status_jabvox, contacts: ccs.count,
      pending: ccs.where(status_jabvox: 'pending').count, completed: ccs.where(status_jabvox: 'completed').count }
  end

  def list_dialer_states(params)
    @account.jabvox_dialer_states.limit(capped_limit(params)).map { |s| dialer_state_view(s) }
  end

  def create_dialer_state(params)
    dialer_state_view(@account.jabvox_dialer_states.create!(params.slice(:name, :color, :position, :is_active).compact_blank))
  end

  def update_dialer_state(params)
    s = @account.jabvox_dialer_states.find(params[:id])
    s.update!(params.slice(:name, :color, :position, :is_active).compact)
    dialer_state_view(s)
  end

  def dialer_state_view(s)
    { id: s.id, name: s.name, color: s.color, position: s.position, is_active: s.is_active }
  end

  def list_dialer_call_logs(params)
    scope = filter_by_date(@account.jabvox_dialer_call_logs, params)
    scope.order(created_at: :desc).limit(capped_limit(params)).map do |log|
      { id: log.id, phone: log.phone_jabvox, status: log.status_jabvox, duration: log.try(:duration_jabvox),
        agent_id: log.agent_id_jabvox, campaign_id: log.jabvox_dialer_campaign_id, typification_id: log.typification_id }
    end
  end

  def typify_dialer_call(params)
    log = if params[:id].present?
            @account.jabvox_dialer_call_logs.find_by(id: params[:id])
          elsif params[:contact_id].present?
            @account.jabvox_dialer_call_logs.where(jabvox_dialer_campaign_contact_id: params[:contact_id]).order(created_at: :desc).first
          end
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'no se encontró la llamada' unless log

    typ_id = params[:typification_id].present? && @account.jabvox_typifications.where(id: params[:typification_id]).pick(:id)
    log.update!(typification_id: (typ_id || nil), notes_jabvox: params[:notes_jabvox].presence || log.notes_jabvox)
    { id: log.id, typification_id: log.typification_id, notes_jabvox: log.notes_jabvox }
  end

  # --- Click-to-call ---
  def list_click_to_call_logs(params)
    scope = filter_by_date(@account.jabvox_call_logs, params)
    scope.order(created_at: :desc).limit(capped_limit(params)).map do |l|
      { id: l.id, phone_number: l.phone_number, status: l.status, note: l.note,
        typification_id: l.typification_id, contact_id: l.contact_id, conversation_id: l.conversation_id }
    end
  end

  def typify_click_to_call(params)
    log = @account.jabvox_call_logs.find(params[:id])
    typ_id = params[:typification_id].presence
    typ_id = nil if typ_id && !@account.jabvox_typifications.exists?(id: typ_id)
    log.update!(typification_id: typ_id, note: params[:note].presence || log.note, status: 'typified')
    { id: log.id, status: log.status, typification_id: log.typification_id, note: log.note }
  end

  # --- CDR ---
  def sync_cdr_now(_params)
    config = @account.jabvox_cdr_config
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'CDR no está configurado' if config&.mysql_host.blank?

    result = Jabvox::CdrSyncService.sync_account(@account)
    { reachable: result[:reachable] != false, inserted: result[:inserted].to_i, updated: result[:updated].to_i }
  end

  def analyze_cdr_call(params)
    pipeline = params[:pipeline_id].present? && @account.jabvox_cdr_pipelines.find_by(id: params[:pipeline_id])
    analysis = Jabvox::CdrAnalysisService.new(account: @account, uniqueid: params[:uniqueid].to_s, pipeline: (pipeline || nil),
                                              force: ActiveModel::Type::Boolean.new.cast(params[:force])).call
    { uniqueid: analysis.uniqueid, status: analysis.status, final_score: analysis.try(:final_score) }
  end

  def typify_cdr_call(params)
    uniqueid = params[:uniqueid].to_s
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'uniqueid requerido' if uniqueid.blank?

    typ = params[:typification_id].present? && @account.jabvox_typifications.find_by(id: params[:typification_id])
    log = @account.jabvox_call_logs.find_by(uniqueid: uniqueid) ||
          @account.jabvox_dialer_call_logs.find_by(uniqueid_jabvox: uniqueid)
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'no se encontró la llamada en el CDR local' unless log

    log.typification = (typ || nil)
    log.status = 'typified' if typ && log.is_a?(JabvoxCallLog)
    log.save!
    { uniqueid: uniqueid, typification_id: typ ? typ.id : nil }
  end

  # --- Tickets ---
  def ticket_view(t)
    { id: t.id, title: t.title_jabvox, status: t.status_jabvox, priority: t.priority_jabvox,
      category_id: t.ticket_category_id, assignee_id: t.assignee_id, contact_id: t.contact_id }
  end

  def create_ticket(params)
    t = @account.jabvox_tickets.new(params.slice(:title_jabvox, :description_jabvox, :ticket_category_id, :priority_jabvox).compact_blank)
    t.requester = @user
    if params[:conversation_id].present?
      conv = @account.conversations.find_by(display_id: params[:conversation_id])
      (t.conversation_id = conv.id) && (t.contact_id = conv.contact_id) if conv
    end
    t.save!
    ticket_view(t)
  end

  def update_ticket(params)
    t = @account.jabvox_tickets.find(params[:id])
    t.update!(params.slice(:title_jabvox, :description_jabvox, :ticket_category_id, :priority_jabvox).compact)
    ticket_view(t)
  end

  def assign_ticket(params)
    t = @account.jabvox_tickets.find(params[:id])
    assignee = params[:assignee_id].present? ? @account.users.find(params[:assignee_id]) : nil
    t.assign_to!(assignee, actor: @user)
    ticket_view(t)
  end

  def change_ticket_status(params)
    t = @account.jabvox_tickets.find(params[:id])
    t.change_status!(params[:status].to_s, actor: @user)
    ticket_view(t)
  end

  def resolve_ticket(params)
    t = @account.jabvox_tickets.find(params[:id])
    t.resolve!(resolution: params[:resolution], resolution_type: params[:resolution_type], actor: @user)
    ticket_view(t)
  end

  def reopen_ticket(params)
    t = @account.jabvox_tickets.find(params[:id])
    t.reopen!(actor: @user)
    ticket_view(t)
  end

  def rate_ticket(params)
    t = @account.jabvox_tickets.find(params[:id])
    t.rate!(rating: params[:rating], comment: params[:comment], actor: @user)
    ticket_view(t)
  end

  def merge_ticket(params)
    source = @account.jabvox_tickets.find(params[:id])
    target = @account.jabvox_tickets.find(params[:target_id])
    Jabvox::Tickets::MergeService.new(source: source, target: target, actor: @user).call
    ticket_view(source)
  end

  def list_ticket_comments(params)
    t = @account.jabvox_tickets.find(params[:id])
    t.comments.order(created_at: :asc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |c|
      { id: c.id, body: c.body_jabvox, private: c.private_jabvox, user_id: c.user_id, created_at: c.created_at }
    end
  end

  def create_ticket_comment(params)
    t = @account.jabvox_tickets.find(params[:id])
    c = t.comments.create!(user: @user, body_jabvox: params[:body].to_s, private_jabvox: !!params[:private])
    { id: c.id, body: c.body_jabvox, private: c.private_jabvox }
  end

  # --- Datos personalizados ---
  def create_custom_table(params)
    t = @account.jabvox_custom_tables.create!(name_jabvox: params[:name_jabvox], description_jabvox: params[:description_jabvox],
                                              kind_jabvox: params[:kind_jabvox].presence || 'single')
    { id: t.id, name: t.name_jabvox, kind: t.kind_jabvox, linked_to: t.linked_to_jabvox }
  end

  def update_custom_table(params)
    t = @account.jabvox_custom_tables.find(params[:id])
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'la tabla "Leads" es del sistema y no se puede editar' if t.try(:system_leads_table?)

    t.update!({ name_jabvox: params[:name_jabvox], description_jabvox: params[:description_jabvox], kind_jabvox: params[:kind_jabvox] }.compact)
    { id: t.id, name: t.name_jabvox, kind: t.kind_jabvox }
  end

  def create_custom_column(params)
    table = @account.jabvox_custom_tables.find(params[:id])
    col = table.jabvox_custom_columns.create!(name_jabvox: params[:name_jabvox], label_jabvox: params[:label_jabvox],
                                              column_type_jabvox: params[:column_type_jabvox], required_jabvox: params[:required_jabvox],
                                              options_jabvox: Array(params[:options_jabvox]), depends_on_jabvox: params[:depends_on_jabvox],
                                              show_when_jabvox: Array(params[:show_when_jabvox]))
    custom_column_view(col)
  end

  def update_custom_column(params)
    table = @account.jabvox_custom_tables.find(params[:id])
    col = table.jabvox_custom_columns.find(params[:column_id])
    attrs = { label_jabvox: params[:label_jabvox], required_jabvox: params[:required_jabvox], position_jabvox: params[:position_jabvox] }.compact
    attrs[:options_jabvox] = Array(params[:options_jabvox]) if params.key?(:options_jabvox)
    col.update!(attrs)
    custom_column_view(col)
  end

  def custom_column_view(col)
    { id: col.id, table_id: col.jabvox_custom_table_id, name: col.name_jabvox, label: col.label_jabvox,
      type: col.column_type_jabvox, required: col.required_jabvox, options: col.options_jabvox }
  end

  def create_custom_table_row(params)
    table = @account.jabvox_custom_tables.find(params[:id])
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'esta tabla no admite filas autónomas' unless standalone_data_table?(table)

    result = Jabvox::CustomRowDataSanitizer.new(table, Hash(params[:data])).call
    return { errors: result.errors } unless result.valid?

    row = table.jabvox_custom_table_rows.create!(data_jabvox: result.data)
    custom_row_view(row)
  end

  def update_custom_table_row(params)
    table = @account.jabvox_custom_tables.find(params[:id])
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'esta tabla no admite filas autónomas' unless standalone_data_table?(table)

    row = table.jabvox_custom_table_rows.standalone.find(params[:row_id])
    result = Jabvox::CustomRowDataSanitizer.new(table, Hash(params[:data])).call
    return { errors: result.errors } unless result.valid?

    row.update!(data_jabvox: result.data)
    custom_row_view(row)
  end

  def standalone_data_table?(table)
    table.linked_to_jabvox.blank? && !table.multi?
  end

  def custom_row_view(row)
    { id: row.id, table_id: row.jabvox_custom_table_id, data: row.data_jabvox || {} }
  end

  def create_quick_button(params)
    b = @account.jabvox_quick_buttons.create!(params.slice(:name_jabvox, :url_jabvox, :color_jabvox, :active_jabvox).compact_blank)
    quick_button_view(b)
  end

  def update_quick_button(params)
    b = @account.jabvox_quick_buttons.find(params[:id])
    b.update!(params.slice(:name_jabvox, :url_jabvox, :color_jabvox, :active_jabvox).compact)
    quick_button_view(b)
  end

  def quick_button_view(button)
    { id: button.id, name: button.name_jabvox, url: button.url_jabvox, color: button.color_jabvox, active: button.active_jabvox }
  end

  # --- Productos ---
  def create_product(params)
    product_view(@account.jabvox_products.create!(product_attrs(params)))
  end

  def update_product(params)
    p = @account.jabvox_products.find(params[:id])
    p.update!(product_attrs(params))
    product_view(p)
  end

  def product_attrs(params)
    params.slice(:name_jabvox, :description_jabvox, :price_jabvox, :tax_percentage_jabvox, :active_jabvox,
                 :product_type_jabvox, :jabvox_currency_id, :jabvox_item_type_id, :jabvox_unit_of_measure_id).compact
  end

  def product_view(product)
    { id: product.id, name: product.name_jabvox, price: product.price_jabvox&.to_s, active: product.active_jabvox,
      type: product.product_type_jabvox }
  end

  def create_order(params)
    order = @account.jabvox_orders.new(params.slice(:contact_id, :conversation_id, :doc_type, :status, :notes).compact)
    order.jabvox_order_items_attributes = order_items_attrs(params[:items])
    compute_order_totals(order)
    order.save!
    order_view(order)
  end

  def update_order(params)
    order = @account.jabvox_orders.find(params[:id])
    order.assign_attributes(params.slice(:doc_type, :status, :notes).compact)
    order.jabvox_order_items_attributes = order_items_attrs(params[:items]) if params.key?(:items)
    compute_order_totals(order)
    order.save!
    order_view(order)
  end

  def send_order_to_alegra(params)
    order = @account.jabvox_orders.find(params[:id])
    Jabvox::AlegraOrderSyncService.new(account: @account, order: order).sync!
    order_view(order.reload)
  rescue StandardError
    { error: 'No se pudo enviar a Alegra. Verifica la integración con el administrador.' }
  end

  def order_items_attrs(items)
    Array(items).map do |i|
      h = i.respond_to?(:to_h) ? i.to_h : i
      h.slice('id', 'jabvox_product_id', 'name_snapshot', 'unit_price', 'quantity', 'discount_pct', 'tax_pct', '_destroy').symbolize_keys
    end
  end

  def compute_order_totals(order)
    items = order.jabvox_order_items.reject(&:marked_for_destruction?)
    items.each do |i|
      base = i.unit_price.to_f * i.quantity.to_f
      i.line_total = base - (base * i.discount_pct.to_f / 100.0) + (base * i.tax_pct.to_f / 100.0)
    end
    subtotal = items.sum { |i| i.unit_price.to_f * i.quantity.to_f }
    discount_total = items.sum { |i| i.unit_price.to_f * i.quantity.to_f * (i.discount_pct.to_f / 100.0) }
    tax_total = items.sum { |i| i.unit_price.to_f * i.quantity.to_f * (i.tax_pct.to_f / 100.0) }
    order.subtotal = subtotal
    order.discount_total = discount_total
    order.tax_total = tax_total
    order.total = subtotal - discount_total + tax_total
  end

  def order_view(order)
    { id: order.id, doc_type: order.doc_type, status: order.status, total: order.total.to_s,
      contact_id: order.contact_id, alegra_number: order.try(:alegra_number),
      items: order.jabvox_order_items.map do |i|
        { id: i.id, product_id: i.jabvox_product_id, name: i.name_snapshot, line_total: i.line_total.to_s }
      end }
  end

  def create_discount(params)
    d = @account.jabvox_discounts.create!(params.slice(:name_jabvox, :description_jabvox, :percentage_jabvox, :active_jabvox).compact)
    { id: d.id, name: d.name_jabvox, percentage: d.percentage_jabvox&.to_s, active: d.active_jabvox }
  end

  def update_discount(params)
    d = @account.jabvox_discounts.find(params[:id])
    d.update!(params.slice(:name_jabvox, :description_jabvox, :percentage_jabvox, :active_jabvox).compact)
    { id: d.id, name: d.name_jabvox, percentage: d.percentage_jabvox&.to_s, active: d.active_jabvox }
  end

  def create_order_status_config(params)
    s = @account.jabvox_order_status_configs.create!(params.slice(:key_jabvox, :label_jabvox, :sort_order_jabvox, :color_jabvox).compact)
    { id: s.id, key: s.key_jabvox, label: s.label_jabvox }
  end

  def update_order_status_config(params)
    s = @account.jabvox_order_status_configs.find(params[:id])
    s.update!(params.slice(:key_jabvox, :label_jabvox, :sort_order_jabvox, :color_jabvox).compact)
    { id: s.id, key: s.key_jabvox, label: s.label_jabvox }
  end

  def create_currency(params)
    c = @account.jabvox_currencies.create!(params.slice(:symbol_jabvox, :name_jabvox, :active_jabvox).compact)
    { id: c.id, symbol: c.symbol_jabvox, name: c.name_jabvox, active: c.active_jabvox }
  end

  def update_currency(params)
    c = @account.jabvox_currencies.find(params[:id])
    c.update!(params.slice(:symbol_jabvox, :name_jabvox, :active_jabvox).compact)
    { id: c.id, symbol: c.symbol_jabvox, name: c.name_jabvox, active: c.active_jabvox }
  end

  def create_item_type(params)
    it = @account.jabvox_item_types.create!(params.slice(:name_jabvox, :active_jabvox).compact)
    { id: it.id, name: it.name_jabvox, active: it.active_jabvox }
  end

  def update_item_type(params)
    it = @account.jabvox_item_types.find(params[:id])
    it.update!(params.slice(:name_jabvox, :active_jabvox).compact)
    { id: it.id, name: it.name_jabvox, active: it.active_jabvox }
  end

  def create_unit_of_measure(params)
    u = @account.jabvox_units_of_measure.create!(params.slice(:name_jabvox, :abbreviation_jabvox, :active_jabvox).compact)
    { id: u.id, name: u.name_jabvox, abbreviation: u.abbreviation_jabvox, active: u.active_jabvox }
  end

  def update_unit_of_measure(params)
    u = @account.jabvox_units_of_measure.find(params[:id])
    u.update!(params.slice(:name_jabvox, :abbreviation_jabvox, :active_jabvox).compact)
    { id: u.id, name: u.name_jabvox, abbreviation: u.abbreviation_jabvox, active: u.active_jabvox }
  end

  def create_tax_rate(params)
    t = @account.jabvox_tax_rates.create!(params.slice(:name_jabvox, :percentage_jabvox, :active_jabvox).compact)
    { id: t.id, name: t.name_jabvox, percentage: t.percentage_jabvox&.to_s, active: t.active_jabvox }
  end

  def update_tax_rate(params)
    t = @account.jabvox_tax_rates.find(params[:id])
    t.update!(params.slice(:name_jabvox, :percentage_jabvox, :active_jabvox).compact)
    { id: t.id, name: t.name_jabvox, percentage: t.percentage_jabvox&.to_s, active: t.active_jabvox }
  end

  # --- Afiliados ---
  def create_affiliate(params)
    affiliate_view(@account.jabvox_affiliates.create!({ name: params[:name], active: params[:active] }.compact))
  end

  def update_affiliate(params)
    a = @account.jabvox_affiliates.find(params[:id])
    a.update!({ name: params[:name], active: params[:active] }.compact)
    affiliate_view(a)
  end

  def regenerate_affiliate_token(params)
    a = @account.jabvox_affiliates.find(params[:id])
    a.regenerate_auth_token!
    affiliate_view(a)
  end

  def regenerate_affiliate_code(params)
    a = @account.jabvox_affiliates.find(params[:id])
    a.regenerate_account_code!
    affiliate_view(a)
  end

  def affiliate_view(affiliate)
    { id: affiliate.id, name: affiliate.name, account_code: affiliate.try(:account_code),
      portal_slug: affiliate.try(:portal_slug), active: affiliate.active }
  end

  # ¿El usuario del agente es administrador de ESTA cuenta? (para reglas como
  # "solo admin envía en nombre de otro"). Nunca se infiere del LLM.
  def admin_account_user?
    @account.account_users.find_by(user_id: @user.id)&.administrator?
  end

  # --- Helpers WhatsApp Grupos ---
  def whatsapp_group_view(group, members: false)
    base = { id: group.id, name: group.try(:name_jabvox) || group.try(:name),
             description: group.try(:description_jabvox) || group.try(:description),
             inbox_id: group.try(:inbox_id) }
    return base unless members

    base.merge(members: whatsapp_group_members(group))
  rescue StandardError
    base
  end

  def whatsapp_group_members(group)
    group.members.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |m|
      { id: m.id, phone: m.try(:phone_jabvox) || m.try(:phone), role: m.try(:role_jabvox) || m.try(:role) }
    end
  end

  # --- Helpers Voice Broadcast ---
  def find_voice_broadcast(id)
    JabvoxVoiceBroadcast.for_account(@account.id).find(id)
  end

  def voice_broadcast_view(bcast, detail: false)
    base = { id: bcast.id, name: bcast.name_jabvox, status: bcast.status_jabvox,
             total_recipients: bcast.try(:total_recipients_jabvox) }
    return base unless detail

    base.merge(caller_id: bcast.try(:caller_id_jabvox), max_concurrent: bcast.try(:max_concurrent_jabvox),
               cps: bcast.try(:cps_jabvox), max_retries: bcast.try(:max_retries_jabvox),
               audio_ready: bcast.try(:audio_ready?), started_at: bcast.try(:started_at_jabvox),
               finished_at: bcast.try(:finished_at_jabvox))
  end

  # Solo los atributos que Hermes envió. Los :json (listas de filtros) se aplican si
  # vienen como Array. NO incluye el audio (Hermes no lo sube).
  def voice_broadcast_attrs(params)
    scalar = params.slice(:name_jabvox, :caller_id_jabvox, :max_concurrent_jabvox, :cps_jabvox,
                          :max_retries_jabvox, :retry_interval_jabvox,
                          :calling_hours_start_jabvox, :calling_hours_end_jabvox).compact
    %i[countries_jabvox management_state_ids_jabvox affiliate_ids_jabvox inbox_ids_jabvox].each do |k|
      scalar[k] = Array(params[k]) if params[k].is_a?(Array)
    end
    scalar
  end

  # --- Helpers Analytics (dashboards/widgets) ---
  def serialize_dashboard(dashboard, with_widgets: false)
    base = { id: dashboard.id, name: dashboard.name_jabvox, description: dashboard.description_jabvox,
             folder_id: dashboard.folder_id, created_at: dashboard.created_at }
    return base unless with_widgets

    base.merge(widgets: dashboard.widgets.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |w|
      serialize_widget(w)
    end)
  end

  def serialize_widget(widget)
    { id: widget.id, dashboard_id: widget.dashboard_id, title: widget.title_jabvox,
      widget_type: widget.widget_type_jabvox, data_source_id: widget.data_source_id,
      has_custom_sql: widget.custom_sql_jabvox.present? }
  end

  # Construye solo los atributos que Hermes envió (los que no manda se dejan
  # intactos). Los :json solo se aplican si vienen como Hash.
  def widget_update_attrs(params)
    attrs = {}
    attrs[:title_jabvox] = params[:title].to_s if params.key?(:title)
    attrs[:widget_type_jabvox] = params[:widget_type].to_s if params.key?(:widget_type)
    attrs[:data_source_id] = resolve_widget_data_source_id(params[:data_source_id]) if params.key?(:data_source_id)
    attrs[:custom_sql_jabvox] = params[:custom_sql] if params.key?(:custom_sql)
    attrs[:query_spec_jabvox] = params[:query_spec] if params[:query_spec].is_a?(Hash)
    attrs[:config_jabvox] = params[:config] if params[:config].is_a?(Hash)
    attrs
  end

  # Aplica el rango de fechas (since/until, ISO) a un scope de reporte. Sin fechas,
  # devuelve el scope intacto. Tolerante a formatos inválidos (los ignora).
  def apply_report_dates(scope, params, table)
    scope = scope.where("#{table}.created_at >= ?", Time.zone.parse(params[:since].to_s).beginning_of_day) if params[:since].present?
    scope = scope.where("#{table}.created_at <= ?", Time.zone.parse(params[:until].to_s).end_of_day) if params[:until].present?
    scope
  rescue ArgumentError, TypeError
    scope
  end

  # Solo acepta un folder que exista en ESTA cuenta; cualquier otro id se ignora
  # (nil) para no fugar/enlazar carpetas ajenas.
  def analytics_folder_id(raw)
    return nil if raw.blank?

    @account.jabvox_analytics_folders.where(id: raw).pick(:id)
  end

  # Valida que la data source pertenezca a ESTA cuenta antes de enlazarla a un
  # widget. Si no existe en la cuenta, se rechaza (no se apunta a fuentes ajenas).
  def resolve_widget_data_source_id(raw)
    return nil if raw.blank?

    id = @account.jabvox_analytics_data_sources.where(id: raw).pick(:id)
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'la fuente de datos no existe en esta cuenta' if id.nil?

    id
  end

  # --- Helpers de daily_series (agrupan por día con groupdate, en la zona de la cuenta) ---

  # Zona horaria para agrupar por día: la que pida el param si es válida, si no la zona por
  # defecto de la app (Time.zone), cayendo a UTC. Valida contra la lista de zonas conocidas
  # para no pasar una cadena arbitraria a groupdate/PG.
  def daily_series_timezone(requested)
    name = requested.to_s.strip
    return name if name.present? && ActiveSupport::TimeZone[name].present?

    Time.zone&.name.presence || 'UTC'
  end

  def messages_daily_series(metric, params, since_at, until_at, tzone)
    scope = @account.messages.reorder(nil)
                    .where('messages.created_at >= ? AND messages.created_at <= ?', since_at, until_at)
    scope = scope.where(message_type: :incoming) if metric == 'messages_incoming'
    scope = scope.where(message_type: :outgoing) if metric == 'messages_outgoing'
    scope = scope.where(private: true, sender_type: 'User') if metric == 'private_notes'
    scope = scope.where(sender_type: 'User', sender_id: params[:agent_id].to_i) if params[:agent_id].to_i.positive?
    scope = scope.joins(:conversation).where(conversations: { inbox_id: params[:inbox_id] }) if params[:inbox_id].to_i.positive?
    scope.group_by_day('messages.created_at', time_zone: tzone).count
  end

  def sales_daily_series(params, since_at, until_at, tzone)
    scope = @account.jabvox_orders.reorder(nil).where(doc_type: 'SALE')
                    .where('jabvox_orders.created_at >= ? AND jabvox_orders.created_at <= ?', since_at, until_at)
    scope = scope.where(created_by_id: params[:agent_id].to_i) if params[:agent_id].to_i.positive?
    scope.group_by_day('jabvox_orders.created_at', time_zone: tzone).sum(:total)
  end

  def conversations_resolved_daily_series(params, since_at, until_at, tzone)
    scope = @account.conversations.reorder(nil).where(status: :resolved)
                    .where('conversations.updated_at >= ? AND conversations.updated_at <= ?', since_at, until_at)
    scope = scope.where(assignee_id: params[:agent_id].to_i) if params[:agent_id].to_i.positive?
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].to_i.positive?
    scope.group_by_day('conversations.updated_at', time_zone: tzone).count
  end
end
# rubocop:enable Metrics/ModuleLength
