# frozen_string_literal: true

class AddRecurrenceAndNoteToJabvoxCalendarEvents < ActiveRecord::Migration[7.1]
  def change
    # recurrence_group_id ties together events created in one multi-slot batch
    # (e.g. Mon 3-4, Tue 5-8, Wed 6-9 share one group id so they can be edited/deleted together).
    add_column :jabvox_calendar_events, :recurrence_group_id, :string
    # note: the message automatically attached to participants (team + external).
    add_column :jabvox_calendar_events, :note, :text

    add_index :jabvox_calendar_events, :recurrence_group_id
  end
end
