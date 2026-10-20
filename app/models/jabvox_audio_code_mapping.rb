# Mapeo explícito, configurado por el usuario, de un código del nombre de archivo
# a una tipificación o a un asesor. El sistema NUNCA infiere estos mapeos: si no
# existe una fila, el parser no resuelve ese código.
class JabvoxAudioCodeMapping < ApplicationRecord
  self.table_name = 'jabvox_audio_code_mappings'

  KINDS = %w[typification advisor].freeze

  belongs_to :account
  belongs_to :typification, class_name: 'JabvoxTypification', optional: true
  belongs_to :advisor, class_name: 'JabvoxAudioAdvisor', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :code, presence: true, length: { maximum: 255 },
                   uniqueness: { scope: %i[account_id kind], case_sensitive: false }
  validate :target_matches_kind

  scope :typifications, -> { where(kind: 'typification') }
  scope :advisors, -> { where(kind: 'advisor') }

  # Resuelve la tipificación mapeada a un código (case-insensitive). nil si no hay.
  def self.typification_for(account, code)
    return nil if code.blank?

    typifications.where(account: account).where('LOWER(code) = ?', code.to_s.strip.downcase)
                 .first&.typification
  end

  # Resuelve el asesor mapeado a un código (case-insensitive). nil si no hay.
  def self.advisor_for(account, code)
    return nil if code.blank?

    advisors.where(account: account).where('LOWER(code) = ?', code.to_s.strip.downcase)
            .first&.advisor
  end

  private

  def target_matches_kind
    if kind == 'typification' && typification_id.blank?
      errors.add(:typification_id, 'es obligatorio para un mapeo de tipificación')
    elsif kind == 'advisor' && advisor_id.blank?
      errors.add(:advisor_id, 'es obligatorio para un mapeo de asesor')
    end
  end
end
