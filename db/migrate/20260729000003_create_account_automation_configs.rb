class CreateAccountAutomationConfigs < ActiveRecord::Migration[7.1]
  # Idempotente: esta migración fue renombrada desde un timestamp anterior para
  # resolver una colisión, así que en instalaciones que ya la corrieron la tabla
  # existe. Solo la crea si falta.
  def change
    return if table_exists?(:account_automation_configs)

    create_table :account_automation_configs do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.boolean :enabled, null: false, default: false
      t.bigint :remote_account_id
      t.datetime :last_provisioned_at
      t.string :last_status
      t.text :last_error

      t.timestamps
    end

    add_index :account_automation_configs, :account_id, unique: true, name: 'index_account_automation_configs_on_account_id_unique'
  end
end
