class CreateJabvoxTasksModule < ActiveRecord::Migration[7.1]
  def change
    # Super-admin toggle for the whole Tasks (kanban) module.
    add_column :accounts, :jabvox_tasks_enabled_jabvox, :boolean, default: false, null: false

    create_boards
    create_stages
    create_tasks
    create_lead_contacts
    create_stage_automations
    create_webhook_deliveries
  end

  private

  # A task board (kanban) per account, e.g. "Operaciones".
  def create_boards
    create_table :jabvox_task_boards do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.integer :position_jabvox, default: 0, null: false
      t.boolean :is_active_jabvox, default: true, null: false
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index [:account_id, :name_jabvox], unique: true
    end
  end

  # Columns of a board.
  def create_stages
    create_table :jabvox_task_stages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :board, null: false, foreign_key: { to_table: :jabvox_task_boards }
      t.string :name_jabvox, null: false
      t.string :color_jabvox, default: '#6b7280', null: false
      t.integer :position_jabvox, default: 0, null: false
      t.timestamps
      t.index [:board_id, :position_jabvox]
    end
  end

  # A task card. Optionally references a lead (read-only link) and carries an optional
  # due_at used by the calendar view.
  def create_tasks
    create_table :jabvox_tasks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :board, null: false, foreign_key: { to_table: :jabvox_task_boards }
      t.references :stage, null: false, foreign_key: { to_table: :jabvox_task_stages }
      t.references :jabvox_lead, foreign_key: true, null: true # optional read-only link
      t.references :assignee, foreign_key: { to_table: :users }, null: true
      t.string :title_jabvox, null: false
      t.text :description_jabvox
      t.string :priority_jabvox, default: 'normal', null: false # low | normal | high | urgent
      t.string :status_jabvox, default: 'open', null: false # open | done
      t.datetime :due_at_jabvox
      t.integer :position_jabvox, default: 0, null: false
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index [:account_id, :board_id]
      t.index [:account_id, :jabvox_lead_id]
      t.index [:account_id, :due_at_jabvox]
      t.index [:stage_id, :position_jabvox]
    end
  end

  # Info-only contact people captured inside a lead for the tasks module. NOT real contacts
  # or leads — purely reference data shown in the right-hand panel, filterable by lead.
  def create_lead_contacts
    create_table :jabvox_task_lead_contacts do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_lead, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.string :role_jabvox, default: '', null: false
      t.string :email_jabvox, default: '', null: false
      t.string :phone_jabvox, default: '', null: false
      t.text :description_jabvox
      t.integer :position_jabvox, default: 0, null: false
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index [:account_id, :jabvox_lead_id]
    end
  end

  # Automations fired when a task enters a stage: send a message (inbox/email/sms) to the
  # lead's contact, POST a signed webhook, or move the card after time/inactivity.
  def create_stage_automations
    create_table :jabvox_task_stage_automations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :stage, null: false, foreign_key: { to_table: :jabvox_task_stages }
      t.string :automation_type_jabvox, null: false # send_message | webhook | move_after_hours | move_if_inactive
      t.string :channel_type_jabvox # inbox | email | sms (for send_message)
      t.text :message_body_jabvox
      t.references :inbox, foreign_key: true, null: true
      t.references :email_template, foreign_key: { to_table: :jabvox_email_templates }, null: true
      t.references :sms_provider, foreign_key: { to_table: :jabvox_sms_providers }, null: true
      t.string :webhook_url_jabvox
      t.text :webhook_secret_jabvox # encrypted
      t.integer :trigger_hours_jabvox
      t.references :target_stage, foreign_key: { to_table: :jabvox_task_stages }, null: true
      t.boolean :active_jabvox, default: true, null: false
      t.timestamps
      t.index [:account_id, :stage_id]
    end
  end

  # Audit trail of outbound task webhooks (status, response code, error).
  def create_webhook_deliveries
    create_table :jabvox_task_webhook_deliveries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :task, foreign_key: { to_table: :jabvox_tasks }, null: true
      t.references :automation, foreign_key: { to_table: :jabvox_task_stage_automations }, null: true
      t.string :url_jabvox, null: false
      t.string :status_jabvox, default: 'pending', null: false # pending | delivered | failed | blocked
      t.integer :response_code_jabvox
      t.text :error_jabvox
      t.jsonb :payload_jabvox, default: {}, null: false
      t.datetime :created_at, null: false
      t.index [:account_id, :created_at]
    end
  end
end
