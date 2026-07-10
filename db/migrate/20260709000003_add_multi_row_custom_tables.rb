class AddMultiRowCustomTables < ActiveRecord::Migration[7.1]
  def up
    # kind: 'single' = one row per lead (current behavior, e.g. the Leads table);
    #       'multi'  = many rows per lead (e.g. Asesorías, Casos).
    add_column :jabvox_custom_tables, :kind_jabvox, :string, default: 'single', null: false

    # The one-row-per-(table, lead) unique index only makes sense for single-kind
    # tables. Drop it and re-add it as a partial index that excludes multi tables,
    # so multi tables can hold many rows per lead while single tables stay 1:1.
    remove_index :jabvox_custom_table_rows, name: 'idx_custom_table_rows_table_lead'
    remove_index :jabvox_custom_table_rows, name: 'idx_custom_table_rows_table_contact'

    # Uniqueness is enforced at the app layer (model) against the table's kind,
    # since a partial index can't reference another table's column. Keep plain
    # (non-unique) indexes for lookup performance — already present for the FK
    # columns, so nothing to add here.

    # Deleting a lead or contact must take its custom rows with it — never block
    # the delete on a RESTRICT FK. Re-create the FKs with ON DELETE CASCADE.
    remove_foreign_key :jabvox_custom_table_rows, :jabvox_leads
    remove_foreign_key :jabvox_custom_table_rows, :contacts
    add_foreign_key :jabvox_custom_table_rows, :jabvox_leads, on_delete: :cascade
    add_foreign_key :jabvox_custom_table_rows, :contacts, on_delete: :cascade
  end

  def down
    remove_foreign_key :jabvox_custom_table_rows, :jabvox_leads
    remove_foreign_key :jabvox_custom_table_rows, :contacts
    add_foreign_key :jabvox_custom_table_rows, :jabvox_leads
    add_foreign_key :jabvox_custom_table_rows, :contacts

    add_index :jabvox_custom_table_rows, %i[jabvox_custom_table_id jabvox_lead_id],
              unique: true, where: 'jabvox_lead_id IS NOT NULL', name: 'idx_custom_table_rows_table_lead'
    add_index :jabvox_custom_table_rows, %i[jabvox_custom_table_id contact_id],
              unique: true, where: 'contact_id IS NOT NULL', name: 'idx_custom_table_rows_table_contact'

    remove_column :jabvox_custom_tables, :kind_jabvox
  end
end
