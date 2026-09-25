# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_affiliates
#
#  id           :bigint           not null, primary key
#  account_code :string           not null
#  active       :boolean          default(TRUE), not null
#  auth_token   :string           not null
#  name         :string           not null
#  owned_jabvox :boolean          default(FALSE), not null
#  portal_slug  :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_jabvox_affiliates_on_account_code           (account_code) UNIQUE
#  index_jabvox_affiliates_on_account_id             (account_id)
#  index_jabvox_affiliates_on_account_id_and_active  (account_id,active)
#  index_jabvox_affiliates_on_auth_token             (auth_token) UNIQUE
#  index_jabvox_affiliates_on_portal_slug            (portal_slug) UNIQUE
#  index_jabvox_affiliates_one_owned_per_account     (account_id) UNIQUE WHERE (owned_jabvox = true)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
#  id           :bigint           not null, primary key
#  account_id   :bigint           not null
#  name         :string           not null
#  account_code :string           not null
#  auth_token   :string           not null
#  active       :boolean          default(TRUE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null

class JabvoxAffiliate < ApplicationRecord
  self.table_name = 'jabvox_affiliates'

  encrypts :account_code, deterministic: true
  encrypts :auth_token, deterministic: true

  belongs_to :account
  has_many :jabvox_affiliate_imports, dependent: :destroy
  has_many :jabvox_affiliate_ip_whitelists, dependent: :destroy

  validates :name, presence: true
  validates :account_code, presence: true, uniqueness: true
  validates :auth_token, presence: true, uniqueness: true
  validates :portal_slug, presence: true, uniqueness: true
  validates :account_id, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :owned, -> { where(owned_jabvox: true) }
  scope :external, -> { where(owned_jabvox: false) }

  before_validation :generate_credentials, on: :create

  # El afiliado propio de la cuenta es intocable: representa "sin afiliado
  # externo" y otros módulos dependen de que exista siempre. Las protecciones
  # viven en el MODELO, no en el controlador, para que ninguna vía (API, consola,
  # otro servicio) pueda saltárselas.
  validate :owned_affiliate_is_immutable, on: :update
  validate :one_owned_affiliate_per_account, on: :create
  before_destroy :prevent_owned_affiliate_destroy

  # El afiliado propio de una cuenta, creándolo si aún no existe. Es idempotente
  # y seguro ante carreras (el índice único decide).
  def self.owned_for!(account)
    owned.find_by(account_id: account.id) ||
      create!(account: account, name: DEFAULT_OWNED_NAME, owned_jabvox: true, active: true)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    owned.find_by!(account_id: account.id)
  end

  # Nombre inicial del afiliado propio. Vive aquí como valor por defecto de la
  # fila que se crea en base de datos, no como un identificador hardcodeado: el
  # afiliado propio se reconoce por owned_jabvox, nunca por su nombre.
  DEFAULT_OWNED_NAME = 'Propio'

  def owned?
    owned_jabvox
  end

  def regenerate_account_code!
    update!(account_code: self.class.generate_account_code)
  end

  def regenerate_auth_token!
    update!(auth_token: self.class.generate_auth_token)
  end

  def regenerate_portal_slug!
    update!(portal_slug: self.class.generate_portal_slug)
  end

  def self.generate_account_code
    "ACC-#{Time.now.to_i * 1000 + rand(999)}-#{SecureRandom.alphanumeric(8).upcase}"
  end

  def self.generate_auth_token
    SecureRandom.alphanumeric(32)
  end

  def self.generate_portal_slug
    loop do
      slug = SecureRandom.alphanumeric(8).downcase
      break slug unless exists?(portal_slug: slug)
    end
  end

  private

  # Un afiliado propio no se renombra, no se desactiva y no cambia de cuenta.
  # Sus credenciales de portal SÍ pueden regenerarse (no es un cambio de
  # identidad y permite revocar un token filtrado).
  PROTECTED_OWNED_ATTRIBUTES = %w[name active owned_jabvox account_id].freeze

  def owned_affiliate_is_immutable
    return unless owned_jabvox_was

    changed_protected = changed & PROTECTED_OWNED_ATTRIBUTES
    return if changed_protected.empty?

    errors.add(:base, I18n.t('errors.jabvox_affiliate.owned_immutable'))
  end

  def one_owned_affiliate_per_account
    return unless owned_jabvox
    return unless self.class.owned.exists?(account_id: account_id)

    errors.add(:base, I18n.t('errors.jabvox_affiliate.owned_already_exists'))
  end

  # Bloquea el borrado del afiliado propio, EXCEPTO cuando desaparece su cuenta:
  # ahí debe irse con ella, o el borrado de la cuenta quedaría atascado contra su
  # propia fila (dependent: :destroy_async en Account).
  def prevent_owned_affiliate_destroy
    return unless owned_jabvox
    return if account_being_destroyed?

    errors.add(:base, I18n.t('errors.jabvox_affiliate.owned_immutable'))
    throw :abort
  end

  # La cuenta ya no existe (borrado en cascada) o está destruyéndose ahora mismo.
  def account_being_destroyed?
    return true if account.nil?

    account.destroyed? || account.marked_for_destruction?
  rescue ActiveRecord::RecordNotFound
    true
  end

  def generate_credentials
    self.account_code ||= self.class.generate_account_code
    self.auth_token ||= self.class.generate_auth_token
    self.portal_slug ||= self.class.generate_portal_slug
  end
end
