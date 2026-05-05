class CreateJabvoxAppStates < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_app_states do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: '#6b7280'
      t.integer :position, default: 0, null: false
      t.boolean :is_active, default: true, null: false
      t.timestamps
    end

    add_index :jabvox_app_states, %i[account_id position]
    add_column :account_users, :jabvox_app_state_id, :integer, null: true
    add_foreign_key :account_users, :jabvox_app_states, column: :jabvox_app_state_id, on_delete: :nullify
  end
end
