class CreateJabvoxResponseBotRoles < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_response_bot_roles do |t|
      t.string :name_jabvox, null: false
      t.text :prompt_jabvox
      t.boolean :active_jabvox, null: false, default: true
      t.timestamps
    end

    add_index :jabvox_response_bot_roles, :name_jabvox, unique: true

    add_column :jabvox_response_bot_configs, :jabvox_response_bot_role_id, :bigint
    add_index :jabvox_response_bot_configs, :jabvox_response_bot_role_id,
              name: 'idx_response_bot_configs_role'
    add_foreign_key :jabvox_response_bot_configs, :jabvox_response_bot_roles,
                    column: :jabvox_response_bot_role_id
  end
end
