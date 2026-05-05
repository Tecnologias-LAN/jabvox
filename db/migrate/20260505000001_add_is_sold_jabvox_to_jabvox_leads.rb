class AddIsSoldJabvoxToJabvoxLeads < ActiveRecord::Migration[7.0]
  def change
    add_column :jabvox_leads, :is_sold_jabvox, :boolean, default: false, null: false
    add_index :jabvox_leads, :is_sold_jabvox
  end
end
