class CreateJabvoxUserCalendarSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_user_calendar_settings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :reminders_enabled, null: false, default: false
      t.text :reminder_minutes

      t.timestamps
    end

    add_index :jabvox_user_calendar_settings, %i[account_id user_id], unique: true

    remove_column :jabvox_smtp_configs, :calendar_reminders_enabled, :boolean
    remove_column :jabvox_smtp_configs, :calendar_reminder_minutes, :text
  end
end
