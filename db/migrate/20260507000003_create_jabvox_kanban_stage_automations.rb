class CreateJabvoxKanbanStageAutomations < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_kanban_stage_automations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_kanban_stage, null: false, foreign_key: true
      t.string :name, null: false
      t.string :channel_type, null: false  # 'inbox', 'email', 'sms'
      t.references :inbox, foreign_key: true, null: true
      t.bigint :jabvox_email_template_id, null: true
      t.bigint :jabvox_sms_provider_id, null: true
      t.text :message_body
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_foreign_key :jabvox_kanban_stage_automations, :jabvox_email_templates, column: :jabvox_email_template_id
    add_foreign_key :jabvox_kanban_stage_automations, :jabvox_sms_providers, column: :jabvox_sms_provider_id
  end
end
