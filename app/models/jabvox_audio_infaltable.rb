# Un infaltable es un comportamiento que NO puede faltar en una llamada de una
# tipificación dada (p. ej. "Generar urgencia", "Acuerdo de entendimiento").
# La IA evalúa cada infaltable aplicable como CUMPLE / NO CUMPLE / NO APLICA /
# NO VERIFICABLE. Los marcados como `optional` (los "Deseable:" del guión) se
# reportan pero no bajan el score.
# == Schema Information
#
# Table name: jabvox_audio_infaltables
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  optional        :boolean          default(FALSE), not null
#  position        :integer          default(0), not null
#  text            :text             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  created_by_id   :bigint
#  typification_id :bigint           not null
#
# Indexes
#
#  index_audio_infaltables_on_account_and_typification  (account_id,typification_id)
#  index_jabvox_audio_infaltables_on_account_id         (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (typification_id => jabvox_typifications.id)
#
class JabvoxAudioInfaltable < ApplicationRecord
  self.table_name = 'jabvox_audio_infaltables'

  belongs_to :account
  belongs_to :typification, class_name: 'JabvoxTypification'
  belongs_to :created_by, class_name: 'User', optional: true

  validates :text, presence: true, length: { maximum: 2000 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
end
