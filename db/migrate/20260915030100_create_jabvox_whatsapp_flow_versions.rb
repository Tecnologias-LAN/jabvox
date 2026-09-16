class CreateJabvoxWhatsappFlowVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_whatsapp_flow_versions do |t|
      t.references :jabvox_whatsapp_flow, null: false, foreign_key: true
      t.integer :version, null: false, default: 1
      t.jsonb :screens_json, null: false, default: []
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end

    add_index :jabvox_whatsapp_flow_versions, [:jabvox_whatsapp_flow_id, :version],
              name: 'idx_jabvox_wa_flow_versions_flow_version'
  end
end
