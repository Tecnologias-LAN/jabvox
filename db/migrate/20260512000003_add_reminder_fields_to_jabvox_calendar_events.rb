class AddReminderFieldsToJabvoxCalendarEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_calendar_events, :contact_id, :bigint
    add_column :jabvox_calendar_events, :remind_before_day, :boolean, default: false, null: false
    add_column :jabvox_calendar_events, :remind_before_hour, :boolean, default: false, null: false

    add_index :jabvox_calendar_events, :contact_id,
              name: 'index_jabvox_calendar_events_on_contact_id'
    add_foreign_key :jabvox_calendar_events, :contacts, column: :contact_id,
                    name: 'fk_jabvox_calendar_events_contact'
  end
end
