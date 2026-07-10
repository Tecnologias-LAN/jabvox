class CreateAccountAutomationConfigs < ActiveRecord::Migration[7.1]
  def change
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
