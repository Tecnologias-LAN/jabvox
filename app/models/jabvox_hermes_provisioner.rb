# El Hermes APROVISIONADOR global (uno, del super admin). Se conecta una sola vez con su
# URL + token de servicio (cifrado); ya sabe aprovisionar/crear más Hermes y trae sus MCPs
# de tareas. NO pertenece a ninguna cuenta: se LIGA a cuentas (JabvoxHermesProvisionerLink),
# y cada cuenta ligada ve el "Chat Aprovisionador".
# == Schema Information
#
# Table name: jabvox_hermes_provisioners
#
#  id                   :bigint           not null, primary key
#  base_url_jabvox      :string
#  last_check_at_jabvox :datetime
#  last_error_jabvox    :text
#  name_jabvox          :string           default("Hermes Aprovisionador"), not null
#  service_token_jabvox :text
#  status_jabvox        :string           default("disconnected"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
class JabvoxHermesProvisioner < ApplicationRecord
  STATUSES = %w[disconnected connected error].freeze

  encrypts :service_token_jabvox if Jabvox.encryption_configured?

  has_many :links, class_name: 'JabvoxHermesProvisionerLink',
                   foreign_key: :hermes_provisioner_id, dependent: :destroy, inverse_of: :hermes_provisioner
  has_many :accounts, through: :links

  validates :status_jabvox, inclusion: { in: STATUSES }

  # Devuelve (creando si hace falta) el aprovisionador global único.
  def self.instance
    first || create!(name_jabvox: 'Hermes Aprovisionador')
  end

  def connected?
    status_jabvox == 'connected' && base_url_jabvox.present? && service_token_jabvox.present?
  end

  def mark_connected!(base_url:, service_token:)
    update!(base_url_jabvox: base_url, service_token_jabvox: service_token,
            status_jabvox: 'connected', last_error_jabvox: nil, last_check_at_jabvox: Time.current)
  end

  def mark_error!(error)
    update!(status_jabvox: 'error', last_error_jabvox: error.to_s.first(255), last_check_at_jabvox: Time.current)
  end

  # Vista segura (nunca el token).
  def safe_summary
    {
      id: id, name: name_jabvox, base_url: base_url_jabvox, status: status_jabvox,
      connected: connected?, linked_accounts: links.where(status_jabvox: 'linked').count,
      last_error: last_error_jabvox, last_check_at: last_check_at_jabvox
    }
  end
end
