class AddFullCoverageFieldsToJabvoxWhatsappTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_whatsapp_templates, :template_kind, :string, null: false, default: 'standard'
    add_column :jabvox_whatsapp_templates, :cards_json, :jsonb, null: false, default: []
    add_column :jabvox_whatsapp_templates, :auth_config_json, :jsonb, null: false, default: {}
    add_column :jabvox_whatsapp_templates, :location_header, :boolean, null: false, default: false
    add_column :jabvox_whatsapp_templates, :limited_time_offer, :boolean, null: false, default: false

    add_index :jabvox_whatsapp_templates, :template_kind
  end
end
