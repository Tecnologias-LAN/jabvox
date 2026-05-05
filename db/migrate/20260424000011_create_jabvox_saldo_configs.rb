class CreateJabvoxSaldoConfigs < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_saldo_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :name_jabvox, null: false, default: ''
      t.string :base_url_jabvox, null: false, default: ''
      t.text :api_key_jabvox
      t.text :api_secret_jabvox
      t.string :saldo_username_jabvox, null: false, default: ''
      t.string :proxy_url_jabvox
      t.boolean :use_proxy_jabvox, null: false, default: false
      t.boolean :is_active_jabvox, null: false, default: true
      t.decimal :cached_balance_jabvox, precision: 15, scale: 2
      t.datetime :balance_updated_at_jabvox

      t.timestamps
    end
  end
end
