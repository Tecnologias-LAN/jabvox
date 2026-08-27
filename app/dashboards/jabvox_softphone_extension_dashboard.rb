require 'administrate/base_dashboard'

# Panel Super Admin: liga una extensión SIP a un usuario, con su credencial de registro
# WebRTC. El sip_secret se cifra en BD y nunca se muestra en claro.
class JabvoxSoftphoneExtensionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    # user con BelongsToSearch (no BelongsTo): el link_to de BelongsTo rompe porque User
    # es STI y el subtipo SuperAdmin choca con el namespace super_admin
    # (genera super_admin_super_admin_path). El search-select del form sí funciona.
    user: Field::BelongsToSearch.with_options(
      class_name: 'User', searchable: true,
      searchable_field: [:name, :email, :id], order: 'id DESC'
    ),
    sip_secret: Field::Password,
    webrtc_enabled: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    user
    webrtc_enabled
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    user
    webrtc_enabled
    created_at
    updated_at
  ].freeze

  # La extensión viene de VoIP (jabvox_user_extensions); aquí solo se captura el secreto
  # SIP del usuario para registrar el softphone por WebRTC.
  FORM_ATTRIBUTES = %i[
    account
    user
    sip_secret
    webrtc_enabled
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(ext)
    "Credencial SIP → #{ext.user&.name || ext.user&.email}"
  end
end
