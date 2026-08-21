# frozen_string_literal: true

# Seed idempotente de los planes Jabvox y una configuración de pasarela inicial.
# Ejecutar con:  rails runner db/seeds/jabvox_billing_seed.rb
#
# Los precios (price_cents) son placeholders: ajústalos desde el panel Super Admin.
# Módulos = nombres cortos (columnas jabvox_*). Límites = cuotas incluidas y precios
# extra por recurso. *_unit_price_cents es el precio por unidad adicional.

plans = [
  {
    slug: 'especial', name: 'Especial', status: :active, sort_order: 1,
    price_cents: 0, currency: 'COP', duration_days: 30, billing_period: :monthly,
    modules: %w[leads lead_delete kanban products tasks calendar email whatsapp_templates
                advanced_automations],
    chatwoot_features: %w[],
    limits: {
      agents: 5, agents_included: 5, agents_unit_price_cents: 10_00,
      inboxes: 2, inboxes_included: 2, inboxes_unit_price_cents: 5_00,
      forms: 0, forms_included: 0, forms_unit_price_cents: 5_00,
      automation_rules: 4, automation_rules_included: 4, automation_rules_unit_price_cents: 2_00,
      advanced_flows: 0, advanced_flows_included: 0, advanced_flows_unit_price_cents: 5_00,
      ai_documents: 0, ai_documents_included: 0, ai_documents_unit_price_cents: 1_00,
      storage_gb: 5, storage_gb_included: 5, storage_gb_unit_price_cents: 3_00
    }
  },
  {
    slug: 'profesional', name: 'Profesional', status: :active, sort_order: 2,
    price_cents: 0, currency: 'COP', duration_days: 30,
    modules: %w[leads lead_delete kanban products tasks calendar email whatsapp_templates
                advanced_automations forms analytics],
    chatwoot_features: %w[],
    limits: {
      agents: 10, agents_included: 10, agents_unit_price_cents: 10_00,
      inboxes: 5, inboxes_included: 5, inboxes_unit_price_cents: 5_00,
      forms: 1, forms_included: 1, forms_unit_price_cents: 5_00,
      automation_rules: 7, automation_rules_included: 7, automation_rules_unit_price_cents: 2_00,
      advanced_flows: 2, advanced_flows_included: 2, advanced_flows_unit_price_cents: 5_00,
      ai_documents: 0, ai_documents_included: 0, ai_documents_unit_price_cents: 1_00,
      analytics_dashboards: 3, analytics_dashboards_included: 3, analytics_dashboards_unit_price_cents: 8_00,
      storage_gb: 15, storage_gb_included: 15, storage_gb_unit_price_cents: 3_00
    }
  },
  {
    slug: 'gerencial', name: 'Gerencial', status: :in_development, sort_order: 3,
    price_cents: 0, currency: 'COP', duration_days: 30,
    modules: %w[leads lead_delete kanban products tasks calendar email whatsapp_templates
                advanced_automations forms analytics data_export lead_import bulk_whatsapp
                sms internal_chat click_to_call cdr ai_chat dialer response_bot customization
                affiliates saldo audio_analysis],
    chatwoot_features: %w[],
    limits: {
      agents: 0, agents_included: 0, agents_unit_price_cents: 10_00,
      inboxes: 0, inboxes_included: 0, inboxes_unit_price_cents: 5_00,
      forms: 3, forms_included: 3, forms_unit_price_cents: 5_00,
      automation_rules: 0, automation_rules_included: 0, automation_rules_unit_price_cents: 2_00,
      advanced_flows: 4, advanced_flows_included: 4, advanced_flows_unit_price_cents: 5_00,
      ai_documents: 0, ai_documents_included: 0, ai_documents_unit_price_cents: 1_00,
      analytics_dashboards: 0, analytics_dashboards_included: 0, analytics_dashboards_unit_price_cents: 8_00,
      storage_gb: 50, storage_gb_included: 50, storage_gb_unit_price_cents: 3_00
    }
  },
  {
    slug: 'premium-call-center', name: 'Premium call center', status: :in_development, sort_order: 4,
    price_cents: 0, currency: 'COP', duration_days: 30,
    modules: %w[leads lead_delete kanban products tasks calendar email whatsapp_templates
                advanced_automations forms analytics data_export lead_import bulk_whatsapp
                sms internal_chat click_to_call cdr ai_chat dialer response_bot customization
                affiliates saldo audio_analysis voip],
    chatwoot_features: %w[],
    limits: {
      agents: 0, agents_included: 0, agents_unit_price_cents: 10_00,
      inboxes: 0, inboxes_included: 0, inboxes_unit_price_cents: 5_00,
      forms: 0, forms_included: 0, forms_unit_price_cents: 5_00,
      automation_rules: 0, automation_rules_included: 0, automation_rules_unit_price_cents: 2_00,
      advanced_flows: 0, advanced_flows_included: 0, advanced_flows_unit_price_cents: 5_00,
      ai_documents: 0, ai_documents_included: 0, ai_documents_unit_price_cents: 1_00,
      analytics_dashboards: 0, analytics_dashboards_included: 0, analytics_dashboards_unit_price_cents: 8_00,
      storage_gb: 100, storage_gb_included: 100, storage_gb_unit_price_cents: 3_00
    }
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

# Configuración de billing: días de gracia para cuentas sin pago.
billing_config = JabvoxBillingConfig.first_or_create!(unpaid_account_cleanup_days: 7)
puts "BillingConfig: ok (cleanup_days=#{billing_config.unpaid_account_cleanup_days})"
