# A storage bucket usable as AI Chat's document source. Mirrored with Audio
# Analysis storages (Jabvox::StorageSyncService): the two modules keep separate
# tables but the same buckets, matched by name — the same pattern CDR/Audio
# pipelines use. Unlike audio storages there is no `use_documents_config`: an AI
# Chat storage always carries its own credentials.
# == Schema Information
#
# Table name: jabvox_ai_chat_storages
#
#  id            :bigint           not null, primary key
#  access_key    :string           default(""), not null
#  bucket_name   :string           default(""), not null
#  bucket_region :string           default("us-east-1"), not null
#  endpoint      :string           default(""), not null
#  name          :string           not null
#  path_prefix   :string           default(""), not null
#  secret_key    :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_ai_chat_storages_on_account_id  (account_id)
#
class JabvoxAiChatStorage < ApplicationRecord
  self.table_name = 'jabvox_ai_chat_storages'

  belongs_to :account

  encrypts :secret_key if Jabvox.encryption_configured?

  validates :name, presence: true, length: { maximum: 150 }

  # Mirror to the Audio Analysis module (only when both modules are enabled).
  # after_commit so the write happens outside this record's transaction.
  after_commit :mirror_to_other_module, on: %i[create update]
  after_commit :remove_other_module_mirror, on: :destroy

  private

  def mirror_to_other_module
    Jabvox::StorageSyncService.mirror(self)
  end

  def remove_other_module_mirror
    Jabvox::StorageSyncService.remove_mirror(self)
  end
end
