require 'administrate/base_dashboard'

# Panel Super Admin de la pasarela de pago. Proveedor activo (bold/wompi/mono), modo
# sandbox, token PÚBLICO, URL de checkout y los SECRETOS (api_key, secret_key), cifrados
# en reposo. Los secretos se muestran como campos de contraseña: nunca se precargan; dejar
# vacío conserva el valor actual (ver el controlador).
class JabvoxPaymentGatewayConfigDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    provider: Field::Select.with_options(collection: JabvoxPaymentGatewayConfig::PROVIDERS),
    active: Field::Boolean,
    sandbox: Field::Boolean,
    public_token: Field::String,
    checkout_base_url: Field::String,
    api_key: Field::Password,
    secret_key: Field::Password,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    provider
    active
    sandbox
  ].freeze

  # Los secretos NO se listan aquí: se muestra solo si están configurados (api_key/
  # secret_key son Field::Password y no exponen el valor).
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    provider
    active
    sandbox
    public_token
    checkout_base_url
    api_key
    secret_key
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    provider
    active
    sandbox
    public_token
    checkout_base_url
    api_key
    secret_key
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(cfg)
    "#{cfg.provider}#{cfg.active? ? ' (activa)' : ''}"
  end
end
