class CreateJabvoxOrderStatusConfigs < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_order_status_configs do |t|
      t.bigint :account_id, null: false
      t.string :key_jabvox, null: false
      t.string :label_jabvox, null: false
      t.integer :sort_order_jabvox, null: false, default: 0
      t.string :color_jabvox, null: false, default: '#6B7280'
      t.timestamps
    end

    add_index :jabvox_order_status_configs, :account_id
    add_index :jabvox_order_status_configs, [:account_id, :key_jabvox], unique: true, name: 'index_jabvox_order_status_account_key'
    add_foreign_key :jabvox_order_status_configs, :accounts
  end
end
