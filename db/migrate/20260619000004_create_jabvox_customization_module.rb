class CreateJabvoxCustomizationModule < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_customization_enabled_jabvox, :boolean, default: false, null: false

    create_table :jabvox_custom_tables do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.integer :position_jabvox, default: 0, null: false
      t.timestamps
    end
    add_index :jabvox_custom_tables, %i[account_id name_jabvox], unique: true

    create_table :jabvox_custom_columns do |t|
      t.references :jabvox_custom_table, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.string :label_jabvox, null: false
      t.string :column_type_jabvox, null: false, default: 'text'
      t.jsonb :options_jabvox, default: []
      t.boolean :required_jabvox, default: false, null: false
      t.integer :position_jabvox, default: 0, null: false
      t.timestamps
    end
    add_index :jabvox_custom_columns, %i[jabvox_custom_table_id name_jabvox], unique: true, name: 'idx_jabvox_custom_columns_table_name'

    create_table :jabvox_quick_buttons do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.string :url_jabvox, null: false
      t.string :color_jabvox, default: '#6b7280'
      t.boolean :active_jabvox, default: true, null: false
      t.integer :position_jabvox, default: 0, null: false
      t.timestamps
    end
  end
end
