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

  # Mirror to the AI Chat module (only when both modules are enabled), matched by
  # name — same pattern as the CDR/Audio pipeline mirror. Storages that reuse the
  # documents config (use_documents_config) are NOT mirrored: they have no own
  # credentials to share, and AI Chat is that very source.
  after_commit :mirror_to_ai_chat, on: %i[create update]
  after_commit :remove_ai_chat_mirror, on: :destroy

  private

  def mirror_to_ai_chat
    Jabvox::StorageSyncService.mirror(self)
  end

  def remove_ai_chat_mirror
    Jabvox::StorageSyncService.remove_mirror(self)
  end
end
