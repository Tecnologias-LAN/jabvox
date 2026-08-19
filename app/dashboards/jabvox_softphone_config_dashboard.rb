require 'administrate/base_dashboard'

# Panel Super Admin de la configuración WebRTC del softphone por cuenta: WSS, dominio SIP,
# codecs, DTMF, autorespuesta, transferencia, STUN/TURN. El turn_secret se cifra en BD.
class JabvoxSoftphoneConfigDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    enabled: Field::Boolean,
    wss_url: Field::String,
    sip_domain: Field::String,
    default_context: Field::String,
    dtmf_mode: Field::Select.with_options(collection: JabvoxSoftphoneConfig::DTMF_MODES),
    auto_answer: Field::Boolean,
    transfer_enabled: Field::Boolean,
    credential_ttl: Field::Number,
    turn_url: Field::String,
    turn_secret: Field::Password,
    codecs: Field::String.with_options(searchable: false),
    stun_servers: Field::String.with_options(searchable: false),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    enabled
    sip_domain
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    enabled
    wss_url
    sip_domain
    default_context
    dtmf_mode
    auto_answer
    transfer_enabled
    credential_ttl
    turn_url
    codecs
    stun_servers
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    account
    enabled
    wss_url
    sip_domain
    default_context
    dtmf_mode
    auto_answer
    transfer_enabled
    credential_ttl
    turn_url
    turn_secret
    codecs
    stun_servers
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(config)
    "Softphone · #{config.account&.name} (#{config.enabled? ? 'activo' : 'inactivo'})"
  end
end
