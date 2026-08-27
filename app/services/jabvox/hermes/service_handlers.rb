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
end
# rubocop:enable Metrics/ModuleLength
