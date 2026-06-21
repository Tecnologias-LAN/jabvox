# == Schema Information
#
# Table name: jabvox_audio_storages
#
#  id                   :bigint           not null, primary key
#  access_key           :string           default(""), not null
#  bucket_name          :string           default(""), not null
#  bucket_region        :string           default("us-east-1"), not null
#  endpoint             :string           default(""), not null
#  name                 :string           not null
#  path_prefix          :string           default(""), not null
#  secret_key           :text
#  use_documents_config :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#
# Indexes
#
#  index_jabvox_audio_storages_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAudioStorage < ApplicationRecord
  self.table_name = 'jabvox_audio_storages'

  belongs_to :account
  has_many :jobs, class_name: 'JabvoxAudioJob', dependent: :nullify, foreign_key: :storage_id, inverse_of: :storage

  encrypts :secret_key if Jabvox.encryption_configured?

  validates :name, presence: true, length: { maximum: 150 }
  validates :bucket_name, presence: true, unless: :use_documents_config?
end
