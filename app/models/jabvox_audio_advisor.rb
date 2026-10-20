# Asesor evaluado por el módulo de QA (la "Liker" en LikeU). Puede existir solo
# dentro del módulo (nombre + external_id, p. ej. el "01" o el usuario corto
# "paramirez" del nombre de archivo) y/o vincularse a un usuario del CRM.
# Así el módulo funciona con o sin CRM.
# == Schema Information
#
# Table name: jabvox_audio_advisors
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#  external_id   :string
#  user_id       :bigint
#
# Indexes
#
#  index_audio_advisors_on_account_and_external_id  (account_id,external_id) UNIQUE
#  index_jabvox_audio_advisors_on_account_id        (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAudioAdvisor < ApplicationRecord
  self.table_name = 'jabvox_audio_advisors'

  belongs_to :account
  # Usuario del CRM al que corresponde este asesor, cuando aplica.
  belongs_to :user, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :results, class_name: 'JabvoxAudioResult', foreign_key: :advisor_id,
                     dependent: :nullify, inverse_of: :advisor

  validates :name, presence: true, length: { maximum: 150 }
  # external_id es opcional, pero cuando existe debe ser único por cuenta: es la
  # llave que usa el parser de nombres de archivo para vincular la llamada.
  validates :external_id, uniqueness: { scope: :account_id }, allow_blank: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  # Busca el asesor que corresponde a un token extraído del nombre de archivo.
  # Prueba, en orden: external_id exacto, nombre exacto (case-insensitive) y
  # nombre contenido (para "AMP Paula Ramírez" → "Paula Ramírez").
  def self.match(account, token)
    token = token.to_s.strip
    return nil if token.blank?

    scope = active.where(account: account)
    scope.find_by(external_id: token) ||
      scope.where('LOWER(name) = ?', token.downcase).first ||
      scope.where('? ILIKE CONCAT(\'%\', name, \'%\')', token).first
  end
end
