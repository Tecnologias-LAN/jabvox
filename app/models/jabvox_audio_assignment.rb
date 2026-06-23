# == Schema Information
#
# Table name: jabvox_audio_assignments
#
#  id              :bigint           not null, primary key
#  file_key        :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  agent_id        :bigint
#  storage_id      :bigint           not null
#  typification_id :bigint
#
# Indexes
#
#  index_jabvox_audio_assignments_on_account_id               (account_id)
#  index_jabvox_audio_assignments_on_agent_id                 (agent_id)
#  index_jabvox_audio_assignments_on_storage_id               (storage_id)
#  index_jabvox_audio_assignments_on_storage_id_and_file_key  (storage_id,file_key) UNIQUE
#  index_jabvox_audio_assignments_on_typification_id          (typification_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (agent_id => users.id)
#  fk_rails_...  (storage_id => jabvox_audio_storages.id)
#  fk_rails_...  (typification_id => jabvox_typifications.id)
#
class JabvoxAudioAssignment < ApplicationRecord
  self.table_name = 'jabvox_audio_assignments'

  belongs_to :account
  belongs_to :storage, class_name: 'JabvoxAudioStorage', foreign_key: :storage_id, inverse_of: false
  belongs_to :typification, class_name: 'JabvoxTypification', optional: true, foreign_key: :typification_id, inverse_of: false
  belongs_to :agent, class_name: 'User', optional: true, foreign_key: :agent_id, inverse_of: false

  validates :file_key, presence: true, uniqueness: { scope: :storage_id }
end
