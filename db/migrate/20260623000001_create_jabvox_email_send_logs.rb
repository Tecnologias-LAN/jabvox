class CreateJabvoxEmailSendLogs < ActiveRecord::Migration[7.1]
  def change
    # One row per outbound email sent through Jabvox SMTP. Lets the analytics
    # Email report count how many emails were sent, by status / source / agent
    # / day. Written best-effort by Jabvox::EmailSenderService — a failure to
    # log must never block the actual delivery.
    create_table :jabvox_email_send_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true, null: true # agent who triggered it (nullable for system/automation)
      t.string :to_email, null: false
      t.string :subject, default: '', null: false
      t.string :status, default: 'sent', null: false # sent | failed
      t.string :source, default: 'manual', null: false # manual | kanban | task | calendar | form | system
      t.text :error_message
      t.datetime :sent_at
      t.timestamps

      t.index %i[account_id created_at]
      t.index %i[account_id status]
    end
  end
end
