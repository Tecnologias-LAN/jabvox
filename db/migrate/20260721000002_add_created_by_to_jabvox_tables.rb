class AddCreatedByToJabvoxTables < ActiveRecord::Migration[7.1]
  # Adds a nullable created_by_id (FK -> users) to every exportable Jabvox table
  # that had no way to know "who created the record" (no created_by/user/agent
  # column). This gives full "who / when" traceability in the external export:
  # `created_by_id` = who, `created_at/updated_at` = when.
  #
  # Additive + nullable, so existing rows stay valid (they predate the tracking).
  # Idempotent: skips a table if the column already exists. Tables that already
  # carry a who-column (user_id, sender_id, assignee_id, agent_id_jabvox,
  # created_by_id), plus `users` and derived rows, are intentionally excluded.
  TABLES = %w[
    jabvox_affiliate_imports jabvox_ai_chat_documents
    jabvox_analytics_dashboard_widgets jabvox_analytics_permissions
    jabvox_analytics_roles jabvox_analytics_widget_filters jabvox_app_states
    jabvox_audio_assignments jabvox_audio_pipelines jabvox_audio_results
    jabvox_bulk_whatsapp_configs jabvox_calendar_external_people jabvox_campaigns
    jabvox_cdr_call_analyses jabvox_cdr_pipelines jabvox_currencies
    jabvox_custom_tables jabvox_deleted_leads jabvox_dialer_campaign_contacts
    jabvox_dialer_campaigns jabvox_dialer_states jabvox_discounts
    jabvox_email_templates jabvox_form_submissions jabvox_forms
    jabvox_ip_whitelists jabvox_item_types jabvox_kanban_conversation_stages
    jabvox_kanban_funnels jabvox_kanban_stage_automations jabvox_kanban_stages
    jabvox_management_answers jabvox_management_questions
    jabvox_order_status_configs jabvox_orders jabvox_products
    jabvox_quick_buttons jabvox_response_bot_documents jabvox_sms_campaigns
    jabvox_sms_messages jabvox_task_automation_runs jabvox_task_stages
    jabvox_task_webhook_deliveries jabvox_tax_rates jabvox_units_of_measure
  ].freeze

  def up
    TABLES.each do |table|
      next unless table_exists?(table)
      next if column_exists?(table, :created_by_id)

      add_reference table, :created_by, foreign_key: { to_table: :users }, null: true, index: true
    end
  end

  def down
    TABLES.each do |table|
      next unless table_exists?(table) && column_exists?(table, :created_by_id)

      remove_reference table, :created_by, foreign_key: { to_table: :users }
    end
  end
end
