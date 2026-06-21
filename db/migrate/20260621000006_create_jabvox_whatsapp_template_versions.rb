class CreateJabvoxWhatsappTemplateVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_whatsapp_template_versions do |t|
      t.references :jabvox_whatsapp_template, null: false, foreign_key: true
      t.integer :version, null: false, default: 1
      t.jsonb :payload, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end
    add_index :jabvox_whatsapp_template_versions, [:jabvox_whatsapp_template_id, :version],
              name: 'idx_jabvox_wa_tpl_versions_tpl_version'
  end
end
