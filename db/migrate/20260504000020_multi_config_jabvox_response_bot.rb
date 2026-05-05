class MultiConfigJabvoxResponseBot < ActiveRecord::Migration[7.1]
  def change
    remove_index :jabvox_response_bot_configs, :account_id
    change_column_null :jabvox_response_bot_configs, :inbox_id, false
    add_index :jabvox_response_bot_configs, [:account_id, :inbox_id],
              unique: true,
              name: 'idx_response_bot_configs_account_inbox'
  end
end
