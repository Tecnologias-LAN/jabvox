class CreateJabvoxWhatsappFlowSubmissions < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_whatsapp_flow_submissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_whatsapp_flow, null: false, foreign_key: true
      t.integer :jabvox_whatsapp_flow_version, null: false
      t.references :contact, null: false, foreign_key: true
      t.references :conversation, foreign_key: true, null: true
      t.references :message, foreign_key: true, null: true
      t.string :flow_token, null: false
      t.string :status, null: false, default: 'completed'
      t.jsonb :raw_response_json, null: false, default: {}
      t.datetime :completed_at, null: false
      t.timestamps
    end

    add_index :jabvox_whatsapp_flow_submissions, [:account_id, :jabvox_whatsapp_flow_id],
              name: 'idx_jabvox_wa_flow_subs_account_flow'
    add_index :jabvox_whatsapp_flow_submissions, [:account_id, :flow_token], unique: true,
                                                                             name: 'idx_jabvox_wa_flow_subs_account_flow_token'
  end
end
