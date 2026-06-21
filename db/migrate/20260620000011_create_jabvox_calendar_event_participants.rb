# frozen_string_literal: true

class CreateJabvoxCalendarEventParticipants < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_calendar_event_participants do |t|
      t.references :jabvox_calendar_event, null: false, foreign_key: true, index: { name: 'idx_calendar_participants_on_event' }
      # Polymorphic-ish: a participant is EITHER a team user OR an external person.
      t.references :user, null: true, foreign_key: true
      t.bigint :jabvox_calendar_external_person_id, null: true
      t.text :note
      t.integer :response_status, default: 0, null: false # 0=pending 1=accepted 2=declined
      t.timestamps
    end

    add_index :jabvox_calendar_event_participants, :jabvox_calendar_external_person_id, name: 'idx_calendar_participants_on_external_person'
    add_foreign_key :jabvox_calendar_event_participants, :jabvox_calendar_external_people,
                    column: :jabvox_calendar_external_person_id
  end
end
