class AddTaskCalendarLink < ActiveRecord::Migration[7.1]
  def change
    # Multiple due dates for a task (none / one / many). Each date becomes a calendar event.
    # The single due_at_jabvox column stays as the primary date (kanban + sorting); this jsonb
    # holds the full set when the user picks several.
    add_column :jabvox_tasks, :due_dates_jabvox, :jsonb, default: [], null: false

    # Link calendar events back to the task that created them, so a task can re-sync (replace)
    # its events without touching unrelated events.
    add_reference :jabvox_calendar_events, :jabvox_task,
                  foreign_key: { to_table: :jabvox_tasks }, null: true
  end
end
