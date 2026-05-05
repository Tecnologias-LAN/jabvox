class AddJabvoxAiChatToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_ai_chat_enabled_jabvox, :boolean, null: false, default: false
    add_column :accounts, :jabvox_ai_chat_max_documents_jabvox, :integer, null: false, default: 0
    add_column :accounts, :jabvox_ai_chat_max_open_chats_jabvox, :integer, null: false, default: 0
  end
end
