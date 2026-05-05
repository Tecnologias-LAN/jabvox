class AddAssigneeToJabvoxLeads < ActiveRecord::Migration[7.0]
  def change
    add_reference :jabvox_leads, :assignee, null: true, foreign_key: { to_table: :users }, index: true
  end
end
