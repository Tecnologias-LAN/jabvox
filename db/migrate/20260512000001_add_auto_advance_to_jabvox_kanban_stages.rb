class AddAutoAdvanceToJabvoxKanbanStages < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_kanban_stages, :auto_advance_enabled, :boolean, default: false, null: false
    add_column :jabvox_kanban_stages, :auto_advance_hours, :integer
    add_column :jabvox_kanban_stages, :auto_advance_target_stage_id, :bigint

    add_index :jabvox_kanban_stages, :auto_advance_target_stage_id,
              name: 'index_jabvox_kanban_stages_on_auto_advance_target'
    add_foreign_key :jabvox_kanban_stages, :jabvox_kanban_stages,
                    column: :auto_advance_target_stage_id,
                    name: 'fk_jabvox_kanban_stages_auto_advance_target'
  end
end
