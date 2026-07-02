# Real-time export target: one external database (per account) that mirrors the
# account's data (messages, calls, CDR, contacts, leads, etc.). The module only
# WRITES; credentials are encrypted and never returned to the frontend.
class CreateJabvoxExportTargets < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_export_targets do |t|
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
      t.integer :query_timeout_ms_jabvox, default: 15_000, null: false
      t.boolean :enabled_jabvox, default: false, null: false # export on/off
      t.datetime :schema_built_at_jabvox                     # when tables were last created/updated
      t.string :status_jabvox, default: 'untested', null: false
      t.datetime :last_tested_at_jabvox
      t.datetime :last_export_at_jabvox
      t.string :last_error_jabvox # sanitized, no secrets
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index %i[account_id name_jabvox], unique: true
    end

    add_column :accounts, :jabvox_data_export_enabled_jabvox, :boolean, default: false, null: false
  end
end
