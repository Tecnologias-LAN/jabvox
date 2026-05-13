class CreateJabvoxCalendarEventReminders < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_calendar_event_reminders do |t|
      t.references :jabvox_calendar_event, null: false, foreign_key: true
      t.integer :minutes_before, null: false
      t.datetime :sent_at, null: false
      t.timestamps
    end

    add_index :jabvox_calendar_event_reminders,
              %i[jabvox_calendar_event_id minutes_before],
              unique: true,
              name: 'index_calendar_reminders_event_minutes'
  end
end
