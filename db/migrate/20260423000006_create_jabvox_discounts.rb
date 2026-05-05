class CreateJabvoxDiscounts < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_discounts do |t|
      t.bigint :account_id, null: false
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.decimal :percentage_jabvox, precision: 5, scale: 2, null: false, default: 0
      t.boolean :active_jabvox, null: false, default: true
      t.timestamps
    end

    add_index :jabvox_discounts, :account_id
    add_index :jabvox_discounts, [:account_id, :name_jabvox], unique: true, name: 'index_jabvox_discounts_account_name'
    add_foreign_key :jabvox_discounts, :accounts
  end
end
