# frozen_string_literal: true

class AddSoftDeleteToJabvoxTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_tasks, :deleted_at_jabvox, :datetime
    add_index :jabvox_tasks, %i[account_id deleted_at_jabvox],
              name: 'idx_jabvox_tasks_account_deleted_at'
  end
end
