# Lets an AI Chat config point its documents at a shared storage bucket
# (JabvoxAudioStorage) instead of its own inline bucket columns. NULL keeps the
# existing behavior: documents come from the config's own bucket_*_jabvox fields.
class AddDocumentsStorageToAiChatConfigs < ActiveRecord::Migration[7.0]
  def change
    add_reference :jabvox_ai_chat_configs, :documents_storage_jabvox,
                  null: true, foreign_key: { to_table: :jabvox_audio_storages, on_delete: :nullify }
  end
end
