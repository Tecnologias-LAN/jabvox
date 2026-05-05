class CreateJabvoxInternalChat < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_internal_chats do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name
      t.integer :chat_type, default: 0, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :jabvox_internal_chat_members do |t|
      t.references :chat, null: false, foreign_key: { to_table: :jabvox_internal_chats }
      t.references :user, null: false, foreign_key: true
      t.integer :unread_count, default: 0, null: false
      t.datetime :last_read_at
      t.timestamps
    end
    add_index :jabvox_internal_chat_members, %i[chat_id user_id], unique: true

    create_table :jabvox_internal_messages do |t|
      t.references :chat, null: false, foreign_key: { to_table: :jabvox_internal_chats }
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.text :content, null: false
      t.timestamps
    end

    add_column :accounts, :jabvox_internal_chat_enabled_jabvox, :boolean, default: false, null: false
  end
end
