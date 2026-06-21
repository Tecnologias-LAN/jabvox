class AddImageModelAndMapsToJabvoxResponseBotConfigs < ActiveRecord::Migration[7.0]
  def change
    add_reference :jabvox_response_bot_configs, :jabvox_image_model,
                  foreign_key: { to_table: :jabvox_ai_chat_models },
                  index: { name: :idx_response_bot_configs_image_model },
                  null: true

    add_column :jabvox_response_bot_configs, :google_maps_api_key_jabvox, :string
    add_column :jabvox_response_bot_configs, :company_address_jabvox, :string
    add_column :jabvox_response_bot_configs, :price_per_km_jabvox, :decimal, precision: 10, scale: 2
  end
end
