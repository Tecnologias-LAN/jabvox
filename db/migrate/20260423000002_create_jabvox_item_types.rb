class CreateJabvoxItemTypes < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_item_types do |t|
      t.bigint :account_id, null: false
      t.string :name_jabvox, null: false
      t.boolean :active_jabvox, null: false, default: true
      t.timestamps
    end

    add_index :jabvox_item_types, :account_id
    add_index :jabvox_item_types, [:account_id, :name_jabvox], unique: true, name: 'index_jabvox_item_types_account_name'
    add_foreign_key :jabvox_item_types, :accounts
  end
end
