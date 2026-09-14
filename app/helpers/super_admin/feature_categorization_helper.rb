# Categorización unificada de TODAS las funciones de la cuenta (Chatwoot + Jabvox) por
# área de negocio, para mostrarlas segmentadas en el Super Admin. Una única fuente de
# verdad: dado el nombre interno de una feature, devuelve su categoría. Los canales
# (TikTok, WhatsApp, Instagram, Facebook, Voz, Web, Email) van juntos en "Bandejas y
# Canales"; las integraciones externas en "Integraciones"; etc.
module SuperAdmin::FeatureCategorizationHelper
  # Orden de presentación de las categorías + su ícono.
  FEATURE_CATEGORIES = [
    { key: :channels,    label: 'Bandejas y Canales',    icon: '📥' },
    { key: :integrations, label: 'Integraciones',        icon: '🔌' },
    { key: :ai,          label: 'IA y Bots',             icon: '🤖' },
    { key: :automation,  label: 'Automatización y Flujos', icon: '⚙️' },
    { key: :management,  label: 'Gestión y Equipos',     icon: '👥' },
    { key: :insights,    label: 'Reportes y Búsqueda',   icon: '📊' },
    { key: :other,       label: 'Otros',                 icon: '🧩' }
  ].freeze

  # Reglas de clasificación por nombre interno de la feature. Se evalúan en orden; la
  # primera coincidencia gana. Un array de patrones (String exacto o Regexp).
  CATEGORY_RULES = {
    channels: [
      /\Achannel_/, /\Awhatsapp/, 'inbound_emails', 'email_continuity_on_api_channel',
      'voice_recorder'
    ],
    integrations: [
      'integrations', /_integration\z/, 'shopify_integration',
      'linear_integration', 'notion_integration', 'crm_integration', 'crm_v2',
      'api_and_webhooks', 'data_import'
    ],
    ai: [
      /\Ajabvox_ia/, 'jabvox_v4', /\Acaptain_/, 'agent_bots'
    ],
    automation: %w[
      automations macros canned_responses auto_resolve_conversations
      sla unattended advanced_assignment assignment_v2
      conversation_required_attributes whatsapp_manual_transfer
    ],
    management: %w[
      agent_management team_management inbox_management inbox_view
      custom_roles audit_logs custom_attributes companies crm
      labels saml mentions participating
      contact_jabvox_support_team
    ],
    insights: [
      'reports', 'report_rollup', 'campaigns', /\Ahelp_center/, /\Aadvanced_search/,
      'search_with_gin', 'unread_count_for_filters', 'conversation_unread_counts',
      'csat_review_notes'
    ]
  }.freeze

  # Devuelve la category key (:channels, :ai, …) para el nombre de una feature.
  def self.category_for(feature_name)
    name = feature_name.to_s
    CATEGORY_RULES.each do |cat, patterns|
      return cat if patterns.any? { |p| p.is_a?(Regexp) ? name.match?(p) : name == p }
    end
    :other
  end

  # Agrupa un hash { feature_name => enabled_bool } en categorías, listo para render.
  # Devuelve [{ key:, label:, icon:, items: [[name, display_name, enabled], ...], on: n }, …]
  # en el orden de FEATURE_CATEGORIES; omite categorías vacías. `display_names` mapea
  # nombre interno → nombre visible.
  def self.group(features, display_names)
    buckets = Hash.new { |h, k| h[k] = [] }
    features.each do |name, enabled|
      buckets[category_for(name)] << [name, display_names[name] || name, enabled]
    end

    FEATURE_CATEGORIES.filter_map do |cat|
      items = buckets[cat[:key]]
      next if items.blank?

      items = items.sort_by { |_n, dn, _e| dn.to_s.downcase }
      cat.merge(items: items, on: items.count { |_n, _dn, e| e.present? })
    end
  end
end
