class CreateJabvoxResponseBotConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_response_bot_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.references :jabvox_response_bot_seat, null: true, foreign_key: true
      t.references :inbox, null: true, foreign_key: true
      t.boolean :enabled_jabvox, default: false, null: false
      t.jsonb :active_labels_jabvox, default: %w[proceso_venta proceso_pago quejas_y_reclamos soporte]
      t.timestamps
    end
  end
end
