class CreateJabvoxOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_orders do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :contact_id
      t.bigint :conversation_id
      t.string :doc_type, default: 'QUOTE', null: false
      t.string :status, default: 'draft', null: false
      t.text :notes
      t.decimal :subtotal, precision: 14, scale: 2, default: 0, null: false
      t.decimal :tax_total, precision: 14, scale: 2, default: 0, null: false
      t.decimal :discount_total, precision: 14, scale: 2, default: 0, null: false
      t.decimal :total, precision: 14, scale: 2, default: 0, null: false
      t.timestamps
    end

    add_index :jabvox_orders, :contact_id
    add_index :jabvox_orders, :conversation_id

    create_table :jabvox_order_items do |t|
      t.references :jabvox_order, null: false, foreign_key: true
      t.bigint :jabvox_product_id
      t.string :name_snapshot, null: false
      t.decimal :unit_price, precision: 14, scale: 2, default: 0, null: false
      t.decimal :quantity, precision: 10, scale: 2, default: 1, null: false
      t.decimal :discount_pct, precision: 5, scale: 2, default: 0, null: false
      t.decimal :tax_pct, precision: 5, scale: 2, default: 0, null: false
      t.decimal :line_total, precision: 14, scale: 2, default: 0, null: false
      t.timestamps
    end

    add_index :jabvox_order_items, :jabvox_product_id
  end
end
