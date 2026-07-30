class CreateJabvoxConversationLabelLogs < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:jabvox_conversation_label_logs)

    create_table :jabvox_conversation_label_logs do |t|
      t.integer :account_id, null: false
      t.integer :conversation_id, null: false
      t.string :label_jabvox, null: false
      t.datetime :applied_at_jabvox, null: false
      t.datetime :removed_at_jabvox
      t.timestamps
    end

    add_index :jabvox_conversation_label_logs, [:account_id, :label_jabvox],
              name: 'idx_conv_label_logs_account_label'
    add_index :jabvox_conversation_label_logs, :conversation_id,
              name: 'idx_conv_label_logs_conversation'
    # An open interval (removed_at NULL) is unique per (conversation, label) so we
    # never double-open the same label on one conversation.
    add_index :jabvox_conversation_label_logs, [:conversation_id, :label_jabvox],
              unique: true, where: 'removed_at_jabvox IS NULL',
              name: 'idx_conv_label_logs_open_unique'
  end
end
