class AddCalendarSettingsToJabvoxSmtpConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_smtp_configs, :calendar_reminders_enabled, :boolean, default: false, null: false
    add_column :jabvox_smtp_configs, :calendar_reminder_minutes, :text
  end
end
