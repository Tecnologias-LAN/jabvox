class CreateJabvoxWhatsappTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_whatsapp_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.string :meta_template_id
      t.string :waba_id
      t.string :phone_number_id
      t.string :name, null: false
      t.string :language, null: false, default: 'es'
      t.string :category, null: false, default: 'UTILITY'
      t.string :status, null: false, default: 'PENDING'
      t.string :quality_score
      t.string :header_type
      t.text :header_content
      t.text :body_content
      t.text :footer_content
      t.jsonb :buttons_json, null: false, default: []
      t.jsonb :variables_json, null: false, default: {}
      t.jsonb :meta_json, null: false, default: {}
      t.string :rejected_reason
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end

    add_index :jabvox_whatsapp_templates, :status
    add_index :jabvox_whatsapp_templates, :meta_template_id
    add_index :jabvox_whatsapp_templates, [:account_id, :name, :language],
              name: 'idx_jabvox_wa_templates_account_name_lang'
  end
end
