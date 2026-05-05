class CreateJabvoxResponseBotDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_response_bot_documents do |t|
      t.references :account, null: false, foreign_key: true
      t.string :label_category_jabvox
      t.string :name_jabvox, null: false
      t.string :s3_key_jabvox, null: false
      t.bigint :size_jabvox
      t.string :content_type_jabvox
      t.boolean :enabled_jabvox, default: true, null: false
      t.timestamps
    end

    add_index :jabvox_response_bot_documents, [:account_id, :label_category_jabvox]
    add_index :jabvox_response_bot_documents, [:account_id, :s3_key_jabvox], unique: true
  end
end
