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
  def list_labels(_params)
    @account.labels.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |l| { id: l.id, title: l.title, color: l.color } }
  end

  def create_label(params)
    label = @account.labels.create!(title: params[:title])
    { id: label.id, title: label.title }
  end

  def update_label(params)
    label = @account.labels.find(params[:id])
    label.update!(title: params[:title])
    { id: label.id, title: label.title }
  end

  # Bandejas (solo lectura)
  def list_inboxes(_params)
    @account.inboxes.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |i| { id: i.id, name: i.name, channel_type: i.channel_type } }
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
  def conversations_meta(_params)
    { open: @account.conversations.open.count, total: @account.conversations.count }
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
      sender: @user, inbox_id: conv.inbox_id,
      # Marca el mensaje como enviado por Hermes (bot), no por el usuario técnico ligado.
      # El front muestra este nombre en vez del del usuario.
      additional_attributes: hermes_message_attrs
    )
    { id: msg.id, conversation_id: conv.display_id }
  end

  # Atributos que identifican un mensaje/nota como enviado por el agente Hermes.
  def hermes_message_attrs
    { 'sent_by_hermes' => true, 'hermes_agent_name' => @hermes_name }
  end

  # Nota privada en una conversación (mensaje interno, no visible al cliente).
  def add_private_note(params)
    conv = find_conversation(params[:id])
    msg = conv.messages.create!(
      account_id: @account.id, message_type: :outgoing, content: params[:content],
      private: true, sender: @user, inbox_id: conv.inbox_id,
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
  def list_automation_rules(_params)
    @account.automation_rules.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |r| { id: r.id, name: r.name, active: r.active } }
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

  def list_webhooks(_params)
    @account.webhooks.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |w| webhook_view(w) }
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

  # Leads
  def search_leads(params)
    scope = @account.jabvox_leads
    q = params[:q].to_s.strip
    if q.present?
      # Busca por los datos del CONTACTO del lead (nombre/email/teléfono), no por un campo
      # inexistente. También por lead_number si es numérico.
      scope = scope.joins(:contact)
                   .where('contacts.name ILIKE :q OR contacts.email ILIKE :q OR contacts.phone_number ILIKE :q',
                          q: "%#{q}%")
      scope = scope.or(@account.jabvox_leads.where(lead_number: q.to_i)) if q.match?(/\A\d+\z/)
    end
    scope.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |l| lead_view(l) }
  rescue StandardError
    # Si el join/or falla por alguna razón, cae a búsqueda simple sin romper.
    @account.jabvox_leads.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |l| lead_view(l) }
  end

  def get_lead(params)
    lead_view(@account.jabvox_leads.find(params[:id]))
  end

  # Gestiones (management states)
  def list_management_states(_params)
    @account.jabvox_management_states.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS)
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
  def list_dialer_campaigns(_params)
    @account.jabvox_dialer_campaigns.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS)
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
  def list_sms_campaigns(_params)
    @account.jabvox_sms_campaigns.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |c| sms_view(c) }
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
    { id: hook.id, url: hook.url, webhook_type: hook.webhook_type, subscriptions: hook.subscriptions }
  end

  def sms_view(campaign)
    { id: campaign.id, name: campaign.try(:name), message: campaign.try(:message) }
  end

  def contact_view(contact)
    { id: contact.id, name: contact.name, email: contact.email, phone_number: contact.phone_number }
  end

  def lead_view(lead)
    { id: lead.id, label: lead.try(:label), lead_number: lead.try(:lead_number),
      is_sold: lead.try(:is_sold_jabvox) }
  end

  # --- Análisis de Audio (solo lectura) ---
  def list_audio_jobs(_params)
    @account.jabvox_audio_jobs.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |j|
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

  def list_audio_pipelines(_params)
    @account.jabvox_audio_pipelines.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |p|
      { id: p.id, name: p.try(:name_jabvox) || p.try(:name) }
    end
  end

  # --- Analytics / BD externas (solo lectura; sin credenciales) ---
  def list_analytics_data_sources(_params)
    @account.jabvox_analytics_data_sources.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |d|
      { id: d.id, name: d.name_jabvox, engine: d.engine_jabvox, database: d.database_jabvox }
    end
  end

  def list_analytics_dashboards(_params)
    @account.jabvox_analytics_dashboards.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |d|
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
  def list_tasks(_params)
    @account.jabvox_tasks.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |t|
      { id: t.id, title: t.try(:title_jabvox) || t.try(:title), stage_id: t.try(:stage_id),
        assignee_id: t.try(:assignee_id), created_at: t.created_at }
    end
  end

  # --- Calendario (solo lectura) ---
  def list_calendar_events(_params)
    @account.jabvox_calendar_events.order(start_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |e|
      { id: e.id, title: e.title, start_at: e.start_at, end_at: e.end_at }
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
    svc = Jabvox::Analytics::IntrospectionService.new(data_source: d, user: @user)
    svc.tables
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

  # === Importar leads (pull desde BD externa) ===
  def list_lead_import_sources(_params)
    @account.jabvox_lead_sources.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |s|
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
  def list_data_export_targets(_params)
    @account.jabvox_export_targets.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |t|
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

  def list_products(_params)
    @account.jabvox_products.order(:name_jabvox).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |p|
      { id: p.id, name: p.name_jabvox, price: p.try(:price_jabvox)&.to_s, type: p.try(:product_type_jabvox) }
    end
  end

  def get_product(params)
    p = @account.jabvox_products.find(params[:id])
    { id: p.id, name: p.name_jabvox, price: p.try(:price_jabvox)&.to_s }
  end

  # === Módulos varios (solo lectura) ===
  def list_task_boards(_params)
    @account.jabvox_task_boards.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |b|
      { id: b.id, name: b.try(:name_jabvox) || b.try(:name) }
    end
  end

  def list_tickets(_params)
    @account.jabvox_tickets.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |t|
      { id: t.id, title: t.title_jabvox, status: t.status_jabvox, priority: t.priority_jabvox,
        created_at: t.created_at }
    end
  end

  def get_ticket(params)
    t = @account.jabvox_tickets.find(params[:id])
    { id: t.id, title: t.title_jabvox, status: t.status_jabvox, priority: t.priority_jabvox,
      description: t.description_jabvox, category_id: t.ticket_category_id }
  end

  def list_kanban_funnels(_params)
    @account.jabvox_kanban_funnels.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |f|
      { id: f.id, name: f.try(:name_jabvox) || f.try(:name) }
    end
  end

  def list_flows(_params)
    @account.jabvox_flows.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |f| flow_view(f) }
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
      return { activated: false, error: 'El flujo tiene problemas y no se puede activar.', validation: flow_validation_view(result) } if result.respond_to?(:blocking?) && result.blocking?
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
      d = reg.definition(type) rescue nil
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
    reg.respond_to?(:params_spec) ? (reg.params_spec(type) rescue nil) : nil
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

  def list_bulk_whatsapp_batches(_params)
    @account.jabvox_bulk_whatsapp_batches.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |b|
      { id: b.id, status: b.try(:status_jabvox), total: b.try(:total_rows_jabvox),
        sent: b.try(:sent_count_jabvox), created_at: b.created_at }
    end
  end

  def list_whatsapp_templates(_params)
    @account.jabvox_whatsapp_templates.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |t| whatsapp_template_view(t) }
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

  # Envía una plantilla de WhatsApp APROBADA a un contacto. Crea/reusa su conversación en la
  # bandeja WhatsApp y despacha la plantilla (el canal la manda a Meta). Requiere que la
  # plantilla esté aprobada por Meta y que el contacto tenga teléfono.
  def send_whatsapp_template_to_contact(params)
    template = @account.jabvox_whatsapp_templates.find(params[:template_id])
    contact = @account.contacts.find(params[:contact_id])
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'el contacto no tiene teléfono' if contact.phone_number.blank?

    status = template.try(:status_jabvox) || template.try(:status)
    unless status.to_s.upcase == 'APPROVED'
      return { sent: false, status: status, error: "la plantilla no está aprobada por Meta (estado: #{status}). No se puede enviar hasta que Meta la apruebe." }
    end

    inbox = template.try(:inbox) || @account.inboxes.find_by(id: template.try(:inbox_id))
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'la plantilla no tiene bandeja de WhatsApp asociada' if inbox.nil?

    conversation = whatsapp_conversation_for(contact, inbox)
    tmpl_params = { 'name' => (template.try(:name_jabvox) || template.try(:name)),
                    'category' => template.try(:category), 'language' => template.try(:language) }
    msg = conversation.messages.create!(
      account_id: @account.id, inbox_id: inbox.id, message_type: :outgoing,
      content: template.try(:body) || template.try(:name_jabvox).to_s, sender: @user,
      additional_attributes: { 'template_params' => tmpl_params.compact, 'sent_by_hermes' => true, 'hermes_agent_name' => @hermes_name }
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

  def list_affiliates(_params)
    @account.jabvox_affiliates.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |a|
      { id: a.id, name: a.try(:name_jabvox) || a.try(:name) }
    end
  end

  def list_campaigns(_params)
    @account.jabvox_campaigns.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |c|
      { id: c.id, name: c.try(:name_jabvox) || c.try(:name) }
    end
  end

  def list_cdr_records(_params)
    JabvoxCdrRecord.where(account_id: @account.id).order(calldate: :desc)
                   .limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |r|
      { id: r.id, src: r.src, dst: r.dst, disposition: r.disposition, duration: r.duration, calldate: r.calldate }
    end
  end

  def list_custom_tables(_params)
    @account.jabvox_custom_tables.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |t|
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
  def list_email_templates(_params)
    @account.jabvox_email_templates.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |t| email_template_view(t) }
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
  def list_forms(_params)
    @account.jabvox_forms.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |f| form_view(f) }
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

  def task_view(task)
    { id: task.id, title: task.title_jabvox, board_id: task.board_id, stage_id: task.stage_id,
      assignee_id: task.assignee_id, priority: task.priority_jabvox, status: task.status_jabvox, due_at: task.due_at_jabvox }
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

  def create_task_lead_contact(params)
    c = @account.jabvox_task_lead_contacts.new(params.slice(:jabvox_lead_id, :name_jabvox, :role_jabvox, :email_jabvox,
                                                            :phone_jabvox, :description_jabvox, :position_jabvox).compact_blank)
    c.created_by = @user
    c.save!
    task_lead_contact_view(c)
  end

  def update_task_lead_contact(params)
    c = @account.jabvox_task_lead_contacts.find(params[:id])
    c.update!(params.slice(:name_jabvox, :role_jabvox, :email_jabvox, :phone_jabvox, :description_jabvox, :position_jabvox).compact_blank)
    task_lead_contact_view(c)
  end

  def task_lead_contact_view(c)
    { id: c.id, jabvox_lead_id: c.jabvox_lead_id, name: c.name_jabvox, role: c.role_jabvox, email: c.email_jabvox, phone: c.phone_jabvox }
  end

  # --- Calendario ---
  def create_calendar_event(params)
    attrs = params.slice(:title, :description, :note, :all_day, :event_type, :status, :color, :contact_id).compact_blank
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

  def update_calendar_event(params)
    e = @account.jabvox_calendar_events.find(params[:id])
    e.update!(params.slice(:title, :description, :note, :event_type, :status, :color, :contact_id).compact_blank)
    calendar_event_view(e)
  end

  def calendar_event_view(e)
    { id: e.id, title: e.title, start_at: e.start_at, end_at: e.end_at, all_day: e.all_day,
      event_type: e.event_type, status: e.status, contact_id: e.contact_id }
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
                                                            :active_jabvox, :include_own_leads_jabvox).compact_blank)
    kanban_funnel_view(f)
  end

  def update_kanban_funnel(params)
    f = @account.jabvox_kanban_funnels.find(params[:id])
    f.update!(params.slice(:name_jabvox, :description_jabvox, :position_jabvox, :active_jabvox, :include_own_leads_jabvox).compact_blank)
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

  def redial_dialer_lead(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    cc = c.jabvox_dialer_campaign_contacts.find_by(contact_id: params[:contact_id].to_i)
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'contacto no encontrado en la campaña' unless cc

    cc.destroy!
    { ok: true, campaign_id: c.id, contact_id: params[:contact_id].to_i }
  end

  def exclude_dialer_lead(params)
    c = @account.jabvox_dialer_campaigns.find(params[:id])
    lead = @account.jabvox_leads.find_by(contact_id: params[:contact_id].to_i)
    raise Jabvox::Hermes::ServiceLayer::UnknownAction, 'lead no encontrado' unless lead

    excluded = Array(c.excluded_lead_ids_jabvox).map(&:to_i)
    excluded << lead.id unless excluded.include?(lead.id)
    c.update!(excluded_lead_ids_jabvox: excluded.uniq)
    c.jabvox_dialer_campaign_contacts.find_by(contact_id: params[:contact_id].to_i)&.destroy!
    { ok: true, campaign_id: c.id, contact_id: params[:contact_id].to_i }
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

  def list_dialer_states(_params)
    @account.jabvox_dialer_states.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |s| dialer_state_view(s) }
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

  def list_dialer_call_logs(_params)
    @account.jabvox_dialer_call_logs.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |log|
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
  def list_click_to_call_logs(_params)
    @account.jabvox_call_logs.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |l|
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
      items: order.jabvox_order_items.map { |i| { id: i.id, product_id: i.jabvox_product_id, name: i.name_snapshot, line_total: i.line_total.to_s } } }
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

  # --- Leads (acciones) ---
  def bulk_assign_leads(params)
    assignee = @account.users.find(params[:assignee_id])
    leads = @account.jabvox_leads.where(id: Array(params[:lead_ids]))
    count = leads.count
    leads.update_all(assignee_id: assignee.id) # rubocop:disable Rails/SkipsModelValidations
    Jabvox::LeadConversationAssignmentSync.new(@account).sync_leads(leads.to_a, assignee)
    ActionCable.server.broadcast("account_#{@account.id}",
                                 { event: 'jabvox.leads_assigned', data: { account_id: @account.id, assignee_id: assignee.id, count: count } })
    { assigned: count }
  end

  def bulk_unassign_leads(params)
    leads = @account.jabvox_leads.where(id: Array(params[:lead_ids]))
    count = leads.count
    leads.update_all(assignee_id: nil) # rubocop:disable Rails/SkipsModelValidations
    { unassigned: count }
  end

  def update_lead_details(params)
    lead = @account.jabvox_leads.find(params[:id])
    ActiveRecord::Base.transaction do
      update_lead_contact_fields(lead, params[:contact])
      update_lead_assignee(lead, params) if params.key?(:assignee_id)
      update_lead_campaign(lead, params[:campaign_name]) if params.key?(:campaign_name)
      apply_lead_custom_fields(lead, params[:custom_fields]) if params[:custom_fields].present?
    end
    { id: lead.id }
  rescue ActiveRecord::RecordInvalid => e
    { error: e.record.errors.full_messages.join(', ') }
  end

  def update_lead_custom_fields(params)
    lead = @account.jabvox_leads.find(params[:id])
    raw = params[:custom_fields].respond_to?(:to_h) ? params[:custom_fields].to_h : {}
    result = Jabvox::LeadCustomFieldsSanitizer.new(@account, lead.custom_fields_jabvox, raw).call
    return { error: result.errors.join(', ') } unless result.valid?

    lead.update!(custom_fields_jabvox: result.data)
    { id: lead.id, custom_fields_jabvox: lead.custom_fields_jabvox }
  end

  def claim_lead(params)
    lead = @account.jabvox_leads.find(params[:id])
    lead.update!(assignee_id: @user.id)
    Jabvox::LeadConversationAssignmentSync.new(@account).sync_lead(lead, @user)
    { id: lead.id, assignee_id: @user.id }
  end

  def sync_lead_contacts(_params)
    existing = JabvoxLead.where(account_id: @account.id).select(:contact_id)
    missing_ids = @account.contacts.where.not(id: existing).pluck(:id)
    return { synced: 0 } if missing_ids.empty?

    now = Time.current
    next_number = (JabvoxLead.where(account_id: @account.id).maximum(:lead_number) || 0) + 1
    synced = 0
    missing_ids.each_slice(1000) do |slice|
      rows = slice.map do |contact_id|
        { account_id: @account.id, contact_id: contact_id, lead_number: next_number,
          custom_fields_jabvox: {}, created_at: now, updated_at: now }.tap { next_number += 1 }
      end
      result = JabvoxLead.insert_all(rows, unique_by: %i[account_id contact_id]) # rubocop:disable Rails/SkipsModelValidations
      synced += result.rows.size
    end
    { synced: synced }
  end

  def update_lead_contact_fields(lead, contact_params)
    return if contact_params.blank? || lead.contact.blank?

    cp = contact_params.respond_to?(:to_h) ? contact_params.to_h.symbolize_keys : {}
    attrs = cp.slice(:phone_number, :email).compact
    additional = lead.contact.additional_attributes || {}
    changed = false
    { country: 'country', identification: 'jabvox_identification_number' }.each do |k, attr_key|
      next unless cp.key?(k)

      additional = additional.merge(attr_key => cp[k].to_s.strip)
      changed = true
    end
    lead.contact.additional_attributes = additional if changed
    lead.contact.update!(attrs) if attrs.present? || changed
  end

  def update_lead_assignee(lead, params)
    assignee = params[:assignee_id].present? ? @account.users.find(params[:assignee_id]) : nil
    lead.update!(assignee: assignee)
    Jabvox::LeadConversationAssignmentSync.new(@account).sync_lead(lead, assignee)
  end

  def update_lead_campaign(lead, campaign_name)
    campaign = campaign_name.present? ? JabvoxCampaign.find_or_create_by!(account: @account, name_jabvox: campaign_name.strip) : nil
    lead.update!(jabvox_campaign: campaign)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def apply_lead_custom_fields(lead, custom_fields)
    raw = custom_fields.respond_to?(:to_h) ? custom_fields.to_h : {}
    result = Jabvox::LeadCustomFieldsSanitizer.new(@account, lead.custom_fields_jabvox, raw).call
    lead.update!(custom_fields_jabvox: result.data) if result.valid?
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
end
# rubocop:enable Metrics/ModuleLength
