# frozen_string_literal: true

class CreateJabvoxCalendarExternalPeople < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_calendar_external_people do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.string :phone_number
      t.text :notes
      t.string :color, default: '#0EA5E9'
      t.timestamps
    end

    add_index :jabvox_calendar_external_people, [:account_id, :email]
  end
end
