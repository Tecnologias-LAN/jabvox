# Adds multi-assignee support and an append-only activity log to the Tasks module.
#
# - jabvox_task_assignees: join table between a task and the users responsible for it.
#   The legacy jabvox_tasks.assignee_id is kept as the "primary assignee" and is mirrored
#   from the first member of this table (handled in the model layer).
# - jabvox_task_activities: append-only history of changes to a task (creation, stage move,
#   status/priority/due-date changes, assignee add/remove). Mirrors the analytics audit log.
class CreateJabvoxTaskAssigneesAndActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_task_assignees do |t|
      t.references :task, null: false, foreign_key: { to_table: :jabvox_tasks }
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.timestamps
    end
    add_index :jabvox_task_assignees, %i[task_id user_id], unique: true,
                                                           name: 'index_jabvox_task_assignees_on_task_and_user'

    create_table :jabvox_task_activities do |t|
      t.references :task, null: false, foreign_key: { to_table: :jabvox_tasks }
      t.references :account, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :action_jabvox, null: false
      t.jsonb :metadata_jabvox, null: false, default: {}
      # Append-only: created_at only, no updated_at.
      t.datetime :created_at, null: false
    end
    add_index :jabvox_task_activities, %i[account_id task_id created_at],
              name: 'index_jabvox_task_activities_on_account_task_created'
  end
end
