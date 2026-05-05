class CreateJabvoxAiChatTables < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_ai_chat_models do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false, limit: 150
      t.string :provider_jabvox, null: false, limit: 50
      t.string :model_jabvox, null: false, limit: 200
      t.text :api_key_jabvox
      t.string :base_url_jabvox, limit: 500
      t.boolean :is_default_jabvox, null: false, default: false
      t.timestamps
    end

    create_table :jabvox_ai_chat_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :bucket_url_jabvox, limit: 500
      t.string :bucket_access_key_jabvox, limit: 200
      t.text :bucket_secret_key_jabvox
      t.string :bucket_region_jabvox, limit: 50, default: 'us-east-1'
      t.string :bucket_name_jabvox, limit: 200
      t.boolean :web_search_enabled_jabvox, null: false, default: false
      t.timestamps
    end

    create_table :jabvox_ai_chat_messages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :session_id_jabvox, null: false, limit: 100
      t.string :role_jabvox, null: false, limit: 20
      t.text :content_jabvox, null: false
      t.jsonb :metadata_jabvox, default: {}
      t.timestamps
    end
    add_index :jabvox_ai_chat_messages, [:account_id, :user_id, :session_id_jabvox], name: 'idx_jabvox_ai_chat_messages_session'
    add_index :jabvox_ai_chat_messages, [:account_id, :user_id], name: 'idx_jabvox_ai_chat_messages_user'

    create_table :jabvox_ai_chat_user_permissions do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.boolean :can_use_jabvox, null: false, default: true
      t.boolean :can_use_models_jabvox, null: false, default: true
      t.boolean :can_use_documents_jabvox, null: false, default: true
      t.timestamps
    end
    add_index :jabvox_ai_chat_user_permissions, [:account_id, :user_id], unique: true, name: 'idx_jabvox_ai_chat_permissions_unique'

    create_table :jabvox_ai_chat_documents do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false, limit: 300
      t.string :s3_key_jabvox, null: false, limit: 500
      t.string :content_type_jabvox, limit: 100
      t.bigint :size_jabvox, default: 0
      t.boolean :is_enabled_jabvox, null: false, default: true
      t.timestamps
    end
    add_index :jabvox_ai_chat_documents, [:account_id, :s3_key_jabvox], unique: true, name: 'idx_jabvox_ai_chat_docs_key'
  end
end
