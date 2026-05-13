class AddAutomationTypeToJabvoxKanbanStageAutomations < ActiveRecord::Migration[7.1]
  def change
    change_column_null :jabvox_kanban_stage_automations, :channel_type, true

    add_column :jabvox_kanban_stage_automations, :automation_type, :string,
               null: false, default: 'send_message'
    add_column :jabvox_kanban_stage_automations, :trigger_hours, :integer
    add_column :jabvox_kanban_stage_automations, :target_stage_id, :bigint

    add_index :jabvox_kanban_stage_automations, :target_stage_id,
              name: 'index_jabvox_stage_automations_on_target_stage'
    add_foreign_key :jabvox_kanban_stage_automations, :jabvox_kanban_stages,
                    column: :target_stage_id,
                    name: 'fk_jabvox_stage_automations_target_stage'
  end
end
