class AddLeadCardsToKanbanStages < ActiveRecord::Migration[7.0]
  def change
    change_column_null :jabvox_kanban_conversation_stages, :conversation_id, true

    add_column :jabvox_kanban_conversation_stages, :jabvox_lead_id, :bigint

    add_index :jabvox_kanban_conversation_stages,
              [:jabvox_lead_id, :jabvox_kanban_funnel_id],
              unique: true,
              where: 'jabvox_lead_id IS NOT NULL',
              name: 'index_jabvox_conv_stages_lead_funnel'

    add_foreign_key :jabvox_kanban_conversation_stages, :jabvox_leads,
                    column: :jabvox_lead_id
  end
end
