class AddGinIndexToJabvoxLeadsCustomFields < ActiveRecord::Migration[7.1]
  def change
    add_index :jabvox_leads, :custom_fields_jabvox,
              using: :gin,
              name: 'index_jabvox_leads_on_custom_fields_jabvox'
  end
end
