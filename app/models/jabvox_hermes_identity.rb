# Identidad PROPIA del Hermes de una cuenta (Fase 0: elimina el token admin en el prompt).
#
# Hermes ya no reutiliza el access_token de un usuario admin. En su lugar tiene un
# AccessToken de SERVICIO cuyo owner es esta identidad (polimórfica). Ese token identifica
# a "el Hermes de la cuenta N" y se valida en un middleware que fuerza el account_id y
# audita cada acción — nunca da acceso directo a la BD ni a otra cuenta.
# == Schema Information
#
# Table name: jabvox_hermes_identities
#
#  id                  :bigint           not null, primary key
#  last_seen_at_jabvox :datetime
#  name_jabvox         :string           not null
#  status_jabvox       :string           default("active"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_jabvox_hermes_identities_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxHermesIdentity < ApplicationRecord
  STATUSES = %w[active disabled].freeze

  belongs_to :account
  # El AccessToken de servicio (polimórfico owner). has_secure_token en AccessToken.
  has_many :access_tokens, as: :owner, dependent: :destroy

  validates :name_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }

  # Devuelve (creando si hace falta) la identidad de servicio de la cuenta.
  def self.for_account(account)
    find_or_create_by!(account_id: account.id) do |identity|
      identity.name_jabvox = "hermes_account_#{account.id}"
      identity.status_jabvox = 'active'
    end
  end

  # El token de servicio actual (o uno nuevo). NO es el token de ningún usuario.
  def service_token
    access_tokens.first || access_tokens.create!
  end

  # Rota el token de servicio (revoca el anterior). Para el "rotar credenciales" del super admin.
  def rotate_token!
    transaction do
      access_tokens.destroy_all
      access_tokens.create!
    end
  end

  def active?
    status_jabvox == 'active'
  end
end
