class AddCustomFieldsToJabvoxLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_leads, :custom_fields_jabvox, :jsonb, default: {}, null: false
  end
end
