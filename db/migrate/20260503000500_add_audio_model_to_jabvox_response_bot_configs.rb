class AddAudioModelToJabvoxResponseBotConfigs < ActiveRecord::Migration[7.1]
  def change
    add_reference :jabvox_response_bot_configs, :jabvox_audio_model,
                  null: true,
                  foreign_key: { to_table: :jabvox_ai_chat_models },
                  index: { name: 'idx_response_bot_configs_audio_model' }
  end
end
