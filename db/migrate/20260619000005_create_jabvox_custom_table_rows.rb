class CreateJabvoxCustomTableRows < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_custom_table_rows do |t|
      t.references :jabvox_custom_table, null: false, foreign_key: true
      t.references :jabvox_lead, null: true, foreign_key: true
      t.references :contact, null: true, foreign_key: true
      t.jsonb :data_jabvox, default: {}, null: false
      t.timestamps
    end

    add_index :jabvox_custom_table_rows, %i[jabvox_custom_table_id jabvox_lead_id],
              unique: true,
              where: 'jabvox_lead_id IS NOT NULL',
              name: 'idx_custom_table_rows_table_lead'

    add_index :jabvox_custom_table_rows, %i[jabvox_custom_table_id contact_id],
              unique: true,
              where: 'contact_id IS NOT NULL',
              name: 'idx_custom_table_rows_table_contact'
  end
end
