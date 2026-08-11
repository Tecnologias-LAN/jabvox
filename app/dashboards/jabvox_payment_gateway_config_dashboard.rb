require 'administrate/base_dashboard'

# Panel Super Admin de la pasarela de pago. Selección de proveedor activo (bold/wompi/mono),
# token PÚBLICO y URL de checkout. Los secretos NO se gestionan aquí (viven en .env).
class JabvoxPaymentGatewayConfigDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    provider: Field::Select.with_options(collection: JabvoxPaymentGatewayConfig::PROVIDERS),
    active: Field::Boolean,
    public_token: Field::String,
    checkout_base_url: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    provider
    active
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    provider
    active
    public_token
    checkout_base_url
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    provider
    active
    public_token
    checkout_base_url
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(cfg)
    "#{cfg.provider}#{cfg.active? ? ' (activa)' : ''}"
  end
end
