class AddModelToJabvoxResponseBotConfigs < ActiveRecord::Migration[7.1]
  def change
    add_reference :jabvox_response_bot_configs, :jabvox_ai_chat_model,
                  null: true, foreign_key: true, index: true
  end
end
