class CreateJabvoxProducts < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_products do |t|
      t.bigint :account_id, null: false
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.decimal :price_jabvox, precision: 12, scale: 2, null: false, default: 0
      t.decimal :base_price_jabvox, precision: 12, scale: 2
      t.decimal :tax_percentage_jabvox, precision: 5, scale: 2
      t.decimal :total_price_jabvox, precision: 12, scale: 2
      t.boolean :active_jabvox, null: false, default: true
      t.string :product_type_jabvox, null: false, default: 'product'
      t.integer :integration_item_id_jabvox
      t.bigint :jabvox_currency_id
      t.bigint :jabvox_item_type_id
      t.bigint :jabvox_unit_of_measure_id
      t.timestamps
    end

    add_index :jabvox_products, :account_id
    add_index :jabvox_products, [:account_id, :name_jabvox], unique: true, name: 'index_jabvox_products_account_name'
    add_index :jabvox_products, :jabvox_currency_id
    add_index :jabvox_products, :jabvox_item_type_id
    add_index :jabvox_products, :jabvox_unit_of_measure_id
    add_foreign_key :jabvox_products, :accounts
    add_foreign_key :jabvox_products, :jabvox_currencies
    add_foreign_key :jabvox_products, :jabvox_item_types
    add_foreign_key :jabvox_products, :jabvox_units_of_measure, column: :jabvox_unit_of_measure_id
  end
end
