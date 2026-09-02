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

  def list_conversation_messages(params)
    conv = @account.conversations.find(params[:id])
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
    conv = @account.conversations.includes(:contact, :assignee).find(params[:id])
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
    conv = @account.conversations.find(params[:id])
    msg = conv.messages.create!(
      account_id: @account.id, message_type: :outgoing, content: params[:content],
      sender: @user, inbox_id: conv.inbox_id
    )
    { id: msg.id, conversation_id: conv.display_id }
  end

  # Nota privada en una conversación (mensaje interno, no visible al cliente).
  def add_private_note(params)
    conv = @account.conversations.find(params[:id])
    msg = conv.messages.create!(
      account_id: @account.id, message_type: :outgoing, content: params[:content],
      private: true, sender: @user, inbox_id: conv.inbox_id
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
    { id: rule.id, name: rule.name, active: rule.active }
  end

  # --- Integración por WEBHOOK directo al Hermes de la cuenta ---
  # Hermes se integra como un webhook (no como AgentBot de Jabvox). Jabvox dispara
  # message_created hacia el Hermes de la cuenta; el Hermes responde vía reply_conversation.

  def list_webhooks(_params)
    @account.webhooks.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |w| webhook_view(w) }
  end

  # Webhook Hermes para TODAS las bandejas (account_type). La URL la FIJA Jabvox al endpoint
  # de webhooks del Hermes de la cuenta. Idempotente por (account, url).
  def create_hermes_webhook(_params)
    hook = upsert_hermes_webhook(webhook_type: :account_type, inbox_id: nil)
    webhook_view(hook)
  end

  # Webhook Hermes para UNA bandeja concreta (inbox_type). Chatwoot solo entregará los
  # message_created de ESA inbox → Hermes recibe solo esa bandeja.
  def create_hermes_inbox_webhook(params)
    inbox = @account.inboxes.find(params[:inbox_id]) # scoped → no cross-account
    hook = upsert_hermes_webhook(webhook_type: :inbox_type, inbox_id: inbox.id)
    webhook_view(hook).merge(inbox_id: inbox.id)
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
    scope = scope.where('label ILIKE :q', q: "%#{q}%") if q.present?
    scope.limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map { |l| lead_view(l) }
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
      { id: t.id, subject: t.try(:subject_jabvox) || t.try(:title), status: t.try(:status_jabvox),
        created_at: t.created_at }
    end
  end

  def get_ticket(params)
    t = @account.jabvox_tickets.find(params[:id])
    { id: t.id, subject: t.try(:subject_jabvox) || t.try(:title), status: t.try(:status_jabvox),
      description: t.try(:description_jabvox) }
  end

  def list_kanban_funnels(_params)
    @account.jabvox_kanban_funnels.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |f|
      { id: f.id, name: f.try(:name_jabvox) || f.try(:name) }
    end
  end

  def list_flows(_params)
    @account.jabvox_flows.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |f|
      { id: f.id, name: f.try(:name_jabvox) || f.try(:name), status: f.try(:status_jabvox) }
    end
  end

  def run_flow(params)
    f = @account.jabvox_flows.find(params[:id])
    Jabvox::Flows::RunJob.perform_later(f.id) if defined?(Jabvox::Flows::RunJob)
    { queued: true, flow_id: f.id }
  end

  def list_bulk_whatsapp_batches(_params)
    @account.jabvox_bulk_whatsapp_batches.order(created_at: :desc).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |b|
      { id: b.id, status: b.try(:status_jabvox), total: b.try(:total_rows_jabvox),
        sent: b.try(:sent_count_jabvox), created_at: b.created_at }
    end
  end

  def list_whatsapp_templates(_params)
    @account.jabvox_whatsapp_templates.order(:id).limit(Jabvox::Hermes::ServiceLayer::MAX_ROWS).map do |t|
      { id: t.id, name: t.try(:name_jabvox) || t.try(:name), status: t.try(:status_jabvox) }
    end
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
end
# rubocop:enable Metrics/ModuleLength
