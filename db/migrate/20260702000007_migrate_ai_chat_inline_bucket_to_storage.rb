# Before storages existed, AI Chat kept its bucket credentials inline on
# jabvox_ai_chat_configs (bucket_*_jabvox). Now AI Chat reads documents from a
# JabvoxAiChatStorage. This migration moves each account's inline bucket into a
# real storage named "Documentos" (idempotent) and points the config at it, so
# accounts that already had a working bucket keep working after the switch.
#
# The mirror callbacks propagate the new storage to Audio Analysis when both
# modules are enabled. Encrypted columns are read/written through the models so
# encryption is handled correctly.
class MigrateAiChatInlineBucketToStorage < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    JabvoxAiChatConfig.where.not(bucket_name_jabvox: [nil, '']).find_each do |config|
      # Skip if already pointing at a storage (idempotent re-run).
      next if config.documents_storage_jabvox_id.present?

      account = config.account
      next unless account

      storage = account.jabvox_ai_chat_storages.find_or_initialize_by(name: 'Documentos')
      storage.assign_attributes(
        bucket_name: config.bucket_name_jabvox.to_s,
        endpoint: config.bucket_url_jabvox.to_s,
        bucket_region: config.bucket_region_jabvox.presence || 'us-east-1',
        access_key: config.bucket_access_key_jabvox.to_s,
        secret_key: config.bucket_secret_key_jabvox
      )
      storage.save!

      config.update_column(:documents_storage_jabvox_id, storage.id)
    end
  end

  def down
    # Non-reversible data migration; leave storages/pointers in place.
  end
end
