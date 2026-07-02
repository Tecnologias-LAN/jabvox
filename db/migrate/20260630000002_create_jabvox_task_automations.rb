class CreateJabvoxTaskAutomations < ActiveRecord::Migration[7.1]
  def change
    create_task_automations
    create_task_automation_runs
  end

  private

  # Recurring per-task automation: "send this email/sms/message every N days|weeks|months
  # to the lead / the assignees / the lead contacts / a manual address". Driven by a daily
  # scheduled job that checks next_run_at and dispatches what is due.
  def create_task_automations
    create_table :jabvox_task_automations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: { to_table: :jabvox_tasks }

      t.string :name_jabvox, default: '', null: false
      t.string :channel_jabvox, null: false      # email | sms | inbox
      # comma list of: lead | assignees | lead_contacts | manual
      t.string :recipients_jabvox, default: 'lead', null: false
      t.string :manual_email_jabvox, default: '', null: false
      t.string :manual_phone_jabvox, default: '', null: false

      # Recurrence: every <interval_count> <interval_unit> (day|week|month).
      t.string :interval_unit_jabvox, default: 'day', null: false
      t.integer :interval_count_jabvox, default: 1, null: false

      # Content. For email we can use a stored template; otherwise raw subject/body.
      t.references :email_template, foreign_key: { to_table: :jabvox_email_templates }, null: true
      t.references :inbox, foreign_key: true, null: true
      t.references :sms_provider, foreign_key: { to_table: :jabvox_sms_providers }, null: true
      t.string :subject_jabvox, default: '', null: false
      t.text :body_jabvox

      t.boolean :active_jabvox, default: true, null: false
      t.datetime :start_at_jabvox       # first time it may run (defaults to now on create)
      t.datetime :end_at_jabvox         # optional: stop recurring after this
      t.datetime :next_run_at_jabvox    # when the scheduler should next fire it
      t.datetime :last_run_at_jabvox
      t.integer :runs_count_jabvox, default: 0, null: false

      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps

      t.index [:account_id, :task_id]
      t.index [:active_jabvox, :next_run_at_jabvox]
    end
  end

  # One row per dispatch attempt, so the task view + board/calendar can show what was sent.
  def create_task_automation_runs
    create_table :jabvox_task_automation_runs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: { to_table: :jabvox_tasks }
      t.references :automation, foreign_key: { to_table: :jabvox_task_automations }, null: true

      t.string :channel_jabvox, null: false
      t.string :status_jabvox, default: 'sent', null: false  # sent | partial | failed | skipped
      t.integer :recipients_count_jabvox, default: 0, null: false
      t.text :detail_jabvox       # human-readable summary / error
      t.datetime :run_at_jabvox, null: false

      t.index [:account_id, :task_id, :run_at_jabvox]
    end
  end
end
