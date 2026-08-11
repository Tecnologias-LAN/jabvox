# frozen_string_literal: true

# Seed idempotente de los planes Jabvox y una configuración de pasarela inicial.
# Ejecutar con:  rails runner db/seeds/jabvox_billing_seed.rb
#
# Los precios (price_cents) son placeholders: ajústalos desde el panel Super Admin.
# Módulos = nombres cortos (columnas jabvox_*). Límites = claves de accounts.limits +
# forms/advanced_flows.

plans = [
  {
    slug: 'especial', name: 'Especial', status: :active, sort_order: 1,
    price_cents: 0, currency: 'COP', duration_days: 30, billing_period: :monthly,
    modules: %w[leads lead_delete kanban products tasks calendar email whatsapp_templates
                advanced_automations],
    chatwoot_features: %w[],
    limits: { agents: 5, forms: 0, automation_rules: 4, advanced_flows: 0, ai_documents: 0 }
  },
  {
    slug: 'profesional', name: 'Profesional', status: :active, sort_order: 2,
    price_cents: 0, currency: 'COP', duration_days: 30,
    modules: %w[leads lead_delete kanban products tasks calendar email whatsapp_templates
                advanced_automations forms analytics],
    chatwoot_features: %w[],
    limits: { agents: 10, forms: 1, automation_rules: 7, advanced_flows: 2, ai_documents: 0 }
  },
  {
    slug: 'gerencial', name: 'Gerencial', status: :in_development, sort_order: 3,
    price_cents: 0, currency: 'COP', duration_days: 30,
    modules: %w[leads lead_delete kanban products tasks calendar email whatsapp_templates
                advanced_automations forms analytics data_export lead_import bulk_whatsapp
                sms internal_chat click_to_call cdr ai_chat dialer response_bot customization
                affiliates saldo audio_analysis],
    chatwoot_features: %w[],
    limits: { agents: 0, forms: 3, automation_rules: 0, advanced_flows: 4, ai_documents: 0 }
  },
  {
    slug: 'premium-call-center', name: 'Premium call center', status: :in_development, sort_order: 4,
    price_cents: 0, currency: 'COP', duration_days: 30,
    modules: %w[leads lead_delete kanban products tasks calendar email whatsapp_templates
                advanced_automations forms analytics data_export lead_import bulk_whatsapp
                sms internal_chat click_to_call cdr ai_chat dialer response_bot customization
                affiliates saldo audio_analysis voip],
    chatwoot_features: %w[],
    limits: { agents: 0, forms: 0, automation_rules: 0, advanced_flows: 0, ai_documents: 0 }
  }
]

plans.each do |attrs|
  plan = JabvoxPlan.find_or_initialize_by(slug: attrs[:slug])
  plan.assign_attributes(attrs)
  plan.save!
  puts "Plan #{plan.slug}: #{plan.persisted? ? 'ok' : 'error'}"
end

# Pasarela por defecto: Bold, inactiva hasta configurar sus secretos en .env.
bold = JabvoxPaymentGatewayConfig.find_or_initialize_by(provider: 'bold')
bold.checkout_base_url ||= 'https://checkout.bold.co'
bold.save!
puts "Gateway bold: ok (active=#{bold.active})"
