# frozen_string_literal: true

class JabvoxCalendarModule < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_calendar_enabled_jabvox, :boolean, default: false, null: false

    create_table :jabvox_calendar_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.datetime :start_at, null: false
      t.datetime :end_at, null: false
      t.boolean :all_day, default: false, null: false
      t.integer :event_type, default: 0, null: false  # 0=reminder 1=appointment 2=task
      t.integer :status, default: 0, null: false       # 0=pending 1=done 2=cancelled
      t.string :color, default: '#3B82F6'
      t.timestamps
    end

    add_index :jabvox_calendar_events, [:account_id, :start_at]
    add_index :jabvox_calendar_events, [:account_id, :user_id]
  end
end
