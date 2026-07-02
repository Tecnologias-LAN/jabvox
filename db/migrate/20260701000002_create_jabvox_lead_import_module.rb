# Lead Import module: pull leads from external databases (MySQL/PostgreSQL),
# map external columns to lead fields, and sync (create new leads + update
# existing ones, identified by an external id).
class CreateJabvoxLeadImportModule < ActiveRecord::Migration[7.1]
  def change
    # An external database connection configured to import leads. Credentials are
    # encrypted at the model layer (ActiveRecord::Encryption); never serialized.
    create_table :jabvox_lead_sources do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.string :engine_jabvox, null: false # postgresql | mysql | mariadb
      t.string :host_jabvox
      t.integer :port_jabvox
      t.string :database_jabvox
      t.string :username_jabvox
      t.text :password_jabvox # encrypted
      t.string :ssl_mode_jabvox, default: 'prefer', null: false
      t.boolean :allow_private_network_jabvox, default: false, null: false
      t.integer :query_timeout_ms_jabvox, default: 30_000, null: false
      # Import config, set after connecting:
      t.string :table_jabvox                    # external table to read from
      t.string :external_id_column_jabvox       # column that uniquely identifies a row
      t.jsonb :field_mapping_jabvox, default: {}, null: false # { external_col => { target, kind } }
      t.string :status_jabvox, default: 'untested', null: false
      t.datetime :last_tested_at_jabvox
      t.datetime :last_synced_at_jabvox
      t.jsonb :last_sync_result_jabvox, default: {}, null: false # counts + errors from last run
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index %i[account_id name_jabvox], unique: true
    end

    # Links an external row (external_id) to the lead created/updated from it.
    # This is the relation between "external db id" and "app lead id".
    create_table :jabvox_lead_source_records do |t|
      t.references :lead_source, null: false, foreign_key: { to_table: :jabvox_lead_sources }
      t.references :account, null: false, foreign_key: true
      t.string :external_id_jabvox, null: false
      t.references :jabvox_lead, null: false, foreign_key: true
      t.datetime :last_synced_at_jabvox
      t.timestamps
      t.index %i[lead_source_id external_id_jabvox], unique: true,
              name: 'index_jabvox_lead_source_records_on_source_and_external_id'
    end

    add_column :accounts, :jabvox_lead_import_enabled_jabvox, :boolean, default: false, null: false
  end
end
