class AddNameDescriptionToJabvoxResponseBotConfigs < ActiveRecord::Migration[7.0]
  def change
    add_column :jabvox_response_bot_configs, :name_jabvox, :string
    add_column :jabvox_response_bot_configs, :description_jabvox, :text
  end
end
