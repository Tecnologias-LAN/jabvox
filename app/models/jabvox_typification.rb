# == Schema Information
#
# Table name: jabvox_typifications
#
#  id          :bigint           not null, primary key
#  description :string           default(""), not null
#  is_active   :boolean          default(TRUE), not null
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_jabvox_typifications_on_account_id           (account_id)
#  index_jabvox_typifications_on_account_id_and_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxTypification < ApplicationRecord
  self.table_name = 'jabvox_typifications'

  belongs_to :account
  has_many :call_logs, class_name: 'JabvoxCallLog', dependent: :nullify, foreign_key: :typification_id, inverse_of: :typification
  has_many :dialer_call_logs, class_name: 'JabvoxDialerCallLog', dependent: :nullify, foreign_key: :typification_id, inverse_of: :typification
  has_many :cdr_pipelines, class_name: 'JabvoxCdrPipeline', dependent: :nullify, foreign_key: :typification_id, inverse_of: :typification
  has_many :audio_pipelines, class_name: 'JabvoxAudioPipeline', dependent: :nullify, foreign_key: :typification_id, inverse_of: :typification

  validates :name, presence: true, length: { maximum: 150 }, uniqueness: { scope: :account_id }

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:name) }
end
