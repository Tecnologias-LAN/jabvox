# AI Chat gets its own storages table, mirrored with Audio Analysis storages
# (Jabvox::StorageSyncService) the same way CDR/Audio pipelines mirror: separate
# tables per module, kept in sync by name. Also re-points the AI Chat config's
# documents_storage reference from the audio table to this new one.
class CreateJabvoxAiChatStorages < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_ai_chat_storages do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.string :bucket_name, default: '', null: false
      t.string :bucket_region, default: 'us-east-1', null: false
      t.string :endpoint, default: '', null: false
      t.string :access_key, default: '', null: false
      t.text :secret_key
      t.string :path_prefix, default: '', null: false
      t.timestamps
    end
    add_index :jabvox_ai_chat_storages, :account_id

    # Re-point the documents_storage reference from audio storages (added in the
    # prior migration) to the new AI Chat storages table.
    if foreign_key_exists?(:jabvox_ai_chat_configs, :jabvox_audio_storages, column: :documents_storage_jabvox_id)
      remove_foreign_key :jabvox_ai_chat_configs, column: :documents_storage_jabvox_id
    end
    # Clear any references that pointed at the old (audio) table — the new table
    # is empty, so keeping them would violate the new FK. The mirror backfill
    # will repopulate AI Chat storages from audio ones.
    execute('UPDATE jabvox_ai_chat_configs SET documents_storage_jabvox_id = NULL')
    add_foreign_key :jabvox_ai_chat_configs, :jabvox_ai_chat_storages,
                    column: :documents_storage_jabvox_id, on_delete: :nullify
  end
end
