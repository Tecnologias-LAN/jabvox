class AddIncludeOwnLeadsToKanbanFunnels < ActiveRecord::Migration[7.0]
  def change
    add_column :jabvox_kanban_funnels, :include_own_leads_jabvox, :boolean, default: false, null: false
  end
end
