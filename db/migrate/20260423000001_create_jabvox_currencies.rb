class CreateJabvoxCurrencies < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_currencies do |t|
      t.bigint :account_id, null: false
      t.string :symbol_jabvox, null: false
      t.string :name_jabvox, null: false
      t.boolean :active_jabvox, null: false, default: true
      t.timestamps
    end

    add_index :jabvox_currencies, :account_id
    add_index :jabvox_currencies, [:account_id, :symbol_jabvox], unique: true, name: 'index_jabvox_currencies_account_symbol'
    add_foreign_key :jabvox_currencies, :accounts
  end
end
