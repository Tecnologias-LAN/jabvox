class CreateCaptainMessageReports < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:captain_message_reports)

    create_table :captain_message_reports do |t|
      t.references :account, null: false
      t.references :conversation, null: false
      t.references :message, null: false
      t.references :user, null: false
      t.string :report_reason, null: false
      t.text :description

      t.timestamps
    end
  end
end
