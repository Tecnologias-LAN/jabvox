class CreateJabvoxWhatsappFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_whatsapp_flows do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.string :waba_id, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.text :description
      t.string :status, null: false, default: 'draft'
      t.string :meta_flow_id
      t.string :meta_status
      t.jsonb :screens_json, null: false, default: []
      t.jsonb :validation_errors_json, null: false, default: []
      t.jsonb :meta_json, null: false, default: {}
      t.datetime :published_at
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end

    add_index :jabvox_whatsapp_flows, [:account_id, :meta_flow_id], name: 'idx_jabvox_wa_flows_account_meta_flow_id'
    add_index :jabvox_whatsapp_flows, :status
    add_index :jabvox_whatsapp_flows, [:account_id, :name], name: 'idx_jabvox_wa_flows_account_name'
  end
end
