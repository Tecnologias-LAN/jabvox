# El Hermes APROVISIONADOR global (uno, del super admin). Se conecta una sola vez con su
# URL + token de servicio (cifrado); ya sabe aprovisionar/crear más Hermes y trae sus MCPs
# de tareas. NO pertenece a ninguna cuenta: se LIGA a cuentas (JabvoxHermesProvisionerLink),
# y cada cuenta ligada ve el "Chat Aprovisionador".
# == Schema Information
#
# Table name: jabvox_hermes_provisioners
#
#  id                     :bigint           not null, primary key
#  base_url_jabvox        :string
#  callback_secret_jabvox :text
#  last_check_at_jabvox   :datetime
#  last_error_jabvox      :text
#  name_jabvox            :string           default("Hermes Aprovisionador"), not null
#  service_token_jabvox   :text
#  sessions_path_jabvox   :string           default("/api/sessions"), not null
#  status_jabvox          :string           default("disconnected"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  service_user_id        :bigint
#
# Indexes
#
#  index_jabvox_hermes_provisioners_on_service_user_id  (service_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (service_user_id => users.id)
#
class JabvoxHermesProvisioner < ApplicationRecord
  STATUSES = %w[disconnected connected error].freeze

  encrypts :service_token_jabvox if Jabvox.encryption_configured?
  encrypts :callback_secret_jabvox if Jabvox.encryption_configured?

  # Segundo factor: un USUARIO de servicio real ligado al aprovisionador. El aprovisionador
  # es el ÚNICO con acceso amplio (todas las cuentas, contraseñas incluidas) MENOS borrar;
  # por eso su webhook exige token + usuario de servicio + secreto (doble validación).
  belongs_to :service_user, class_name: 'User', optional: true

  has_many :links, class_name: 'JabvoxHermesProvisionerLink',
                   foreign_key: :hermes_provisioner_id, dependent: :destroy, inverse_of: :hermes_provisioner
  has_many :accounts, through: :links

  validates :status_jabvox, inclusion: { in: STATUSES }

  # Devuelve el aprovisionador global ÚNICO (singleton estricto: siempre el de menor id;
  # nunca crea un segundo). Solo puede existir un token de aprovisionador en la app.
  def self.instance
    order(:id).first || create!(name_jabvox: 'Hermes Aprovisionador')
  end

  def connected?
    status_jabvox == 'connected' && base_url_jabvox.present? && service_token_jabvox.present?
  end

  # Path base de la Sessions API de Hermes (default /api/sessions). Configurable por si el
  # deployment usa otro prefijo. Se combina con base_url (host:puerto ZeroTier).
  def sessions_path
    sessions_path_jabvox.presence || '/api/sessions'
  end

  # Doble validación del callback: token de servicio Y usuario de servicio Y secreto deben
  # coincidir (comparación en tiempo constante). Devuelve true solo si TODO cuadra.
  def valid_callback?(token:, service_user_id:, secret:)
    return false unless connected? && service_user_id_value.present?
    return false unless service_user_id.to_i == service_user_id_value

    secure_eq?(token, service_token_jabvox) && secure_eq?(secret, callback_secret_jabvox)
  end

  def service_user_id_value
    self[:service_user_id]
  end

  def mark_connected!(base_url:, service_token:, service_user: nil, callback_secret: nil)
    attrs = { base_url_jabvox: base_url, service_token_jabvox: service_token,
              status_jabvox: 'connected', last_error_jabvox: nil, last_check_at_jabvox: Time.current }
    attrs[:service_user_id] = service_user.id if service_user
    attrs[:callback_secret_jabvox] = callback_secret if callback_secret.present?
    update!(attrs)
  end

  def mark_error!(error)
    update!(status_jabvox: 'error', last_error_jabvox: error.to_s.first(255), last_check_at_jabvox: Time.current)
  end

  # Vista segura (nunca el token ni el secreto).
  def safe_summary
    {
      id: id, name: name_jabvox, base_url: base_url_jabvox, status: status_jabvox,
      connected: connected?, linked_accounts: links.where(status_jabvox: 'linked').count,
      service_user_id: service_user_id_value, has_callback_secret: callback_secret_jabvox.present?,
      sessions_path: sessions_path, last_error: last_error_jabvox, last_check_at: last_check_at_jabvox
    }
  end

  private

  # Comparación en tiempo constante que tolera nils sin lanzar.
  def secure_eq?(given, expected)
    given.present? && expected.present? &&
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected.to_s)
  end
end
