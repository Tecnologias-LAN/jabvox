# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_10_26_000001) do
  # These extensions should be enabled to support this database
  enable_extension "pg_stat_statements"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "unaccent"
  enable_extension "vector"


  # Función IMMUTABLE para búsqueda insensible a acentos (módulo Jabvox Tickets).
  unless connection.select_value("SELECT to_regprocedure('jabvox_immutable_unaccent(text)') IS NOT NULL")
    execute("CREATE FUNCTION jabvox_immutable_unaccent(text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS $func$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $func$")
  end
  create_table "access_tokens", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "expires_at"
    t.index ["expires_at"], name: "index_access_tokens_on_expires_at"
    t.index ["owner_type", "owner_id"], name: "index_access_tokens_on_owner_type_and_owner_id"
    t.index ["token"], name: "index_access_tokens_on_token", unique: true
  end

  create_table "account_automation_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "enabled", default: false, null: false
    t.bigint "remote_account_id"
    t.datetime "last_provisioned_at"
    t.string "last_status"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "max_flows"
    t.text "api_key_jabvox"
    t.string "api_key_prefix_jabvox"
    t.datetime "api_key_set_at_jabvox"
    t.bigint "automations_user_id"
    t.integer "automations_state", default: 0, null: false
    t.datetime "automations_user_set_at"
    t.bigint "automations_user_set_by_id"
    t.string "automations_user_set_ip"
    t.index ["account_id"], name: "index_account_automation_configs_on_account_id_unique", unique: true
    t.index ["automations_user_id"], name: "index_account_automation_configs_on_automations_user_id"
  end

  create_table "account_saml_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "sso_url"
    t.text "certificate"
    t.string "sp_entity_id"
    t.string "idp_entity_id"
    t.json "role_mappings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_saml_settings_on_account_id"
  end

  create_table "account_users", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "user_id"
    t.integer "role", default: 0
    t.bigint "inviter_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "active_at", precision: nil
    t.integer "availability", default: 0, null: false
    t.boolean "auto_offline", default: true, null: false
    t.bigint "custom_role_id"
    t.bigint "agent_capacity_policy_id"
    t.integer "jabvox_app_state_id"
    t.string "jabvox_dialer_state", default: "inactive"
    t.datetime "jabvox_app_state_changed_at"
    t.datetime "jabvox_dialer_state_changed_at"
    t.index ["account_id", "user_id"], name: "uniq_user_id_per_account_id", unique: true
    t.index ["account_id"], name: "index_account_users_on_account_id"
    t.index ["agent_capacity_policy_id"], name: "index_account_users_on_agent_capacity_policy_id"
    t.index ["custom_role_id"], name: "index_account_users_on_custom_role_id"
    t.index ["user_id"], name: "index_account_users_on_user_id"
  end

  create_table "accounts", id: :serial, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "locale", default: 0
    t.string "domain", limit: 100
    t.string "support_email", limit: 100
    t.bigint "feature_flags", default: 0, null: false
    t.integer "auto_resolve_duration"
    t.jsonb "limits", default: {}
    t.jsonb "custom_attributes", default: {}
    t.integer "status", default: 0
    t.jsonb "internal_attributes", default: {}, null: false
    t.jsonb "settings", default: {}
    t.boolean "jabvox_kanban_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_products_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_voip_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_sms_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_ai_chat_enabled_jabvox", default: false, null: false
    t.integer "jabvox_ai_chat_max_documents_jabvox", default: 0, null: false
    t.integer "jabvox_ai_chat_max_open_chats_jabvox", default: 0, null: false
    t.boolean "jabvox_saldo_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_dialer_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_leads_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_affiliates_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_calendar_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_internal_chat_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_response_bot_enabled_jabvox", default: false, null: false
    t.string "jabvox_acento_jabvox"
    t.boolean "jabvox_email_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_forms_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_cdr_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_audio_analysis_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_click_to_call_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_customization_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_analytics_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_whatsapp_templates_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_tasks_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_bulk_whatsapp_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_lead_import_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_data_export_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_lead_delete_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_advanced_automations_enabled_jabvox", default: false, null: false
    t.bigint "feature_flags_ext_1", default: 0, null: false
    t.boolean "jabvox_whatsapp_groups_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_voice_broadcast_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_tickets_enabled_jabvox", default: false, null: false
    t.bigint "jabvox_plan_id"
    t.datetime "jabvox_plan_expires_at"
    t.boolean "jabvox_softphone_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_ai_chat_provisioning_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_auto_renew", default: false, null: false
    t.boolean "jabvox_whatsapp_flows_enabled_jabvox", default: false, null: false
    t.boolean "jabvox_ip_whitelist_enabled_jabvox", default: true, null: false
    t.boolean "jabvox_management_states_enabled_jabvox", default: true, null: false
    t.boolean "jabvox_field_security_enabled_jabvox", default: true, null: false
    t.boolean "jabvox_conversation_workflow_enabled_jabvox", default: true, null: false
    t.boolean "jabvox_sla_enabled_jabvox", default: true, null: false
    t.boolean "jabvox_audit_logs_enabled_jabvox", default: true, null: false
    t.boolean "jabvox_canned_responses_enabled_jabvox", default: true, null: false
    t.index ["jabvox_plan_id"], name: "index_accounts_on_jabvox_plan_id"
    t.index ["status"], name: "index_accounts_on_status"
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_bot_inboxes", force: :cascade do |t|
    t.integer "inbox_id"
    t.integer "agent_bot_id"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "account_id"
  end

  create_table "agent_bots", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.string "outgoing_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.integer "bot_type", default: 0
    t.jsonb "bot_config", default: {}
    t.string "secret"
    t.index ["account_id"], name: "index_agent_bots_on_account_id"
  end

  create_table "agent_capacity_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.jsonb "exclusion_rules", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_agent_capacity_policies_on_account_id"
  end

  create_table "applied_slas", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sla_status", default: 0
    t.index ["account_id", "sla_policy_id", "conversation_id"], name: "index_applied_slas_on_account_sla_policy_conversation", unique: true
    t.index ["account_id"], name: "index_applied_slas_on_account_id"
    t.index ["conversation_id"], name: "index_applied_slas_on_conversation_id"
    t.index ["sla_policy_id"], name: "index_applied_slas_on_sla_policy_id"
  end

  create_table "article_embeddings", force: :cascade do |t|
    t.bigint "article_id", null: false
    t.text "term", null: false
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_article_embeddings_on_embedding", using: :ivfflat
  end

  create_table "articles", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.integer "category_id"
    t.integer "folder_id"
    t.string "title"
    t.text "description"
    t.text "content"
    t.integer "status"
    t.integer "views"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "author_id"
    t.bigint "associated_article_id"
    t.jsonb "meta", default: {}
    t.string "slug", null: false
    t.integer "position"
    t.string "locale", default: "en", null: false
    t.string "draft_title"
    t.text "draft_content"
    t.index ["account_id"], name: "index_articles_on_account_id"
    t.index ["associated_article_id"], name: "index_articles_on_associated_article_id"
    t.index ["author_id"], name: "index_articles_on_author_id"
    t.index ["portal_id"], name: "index_articles_on_portal_id"
    t.index ["slug"], name: "index_articles_on_slug", unique: true
    t.index ["status"], name: "index_articles_on_status"
    t.index ["views"], name: "index_articles_on_views"
  end

  create_table "assignment_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.integer "assignment_order", default: 0, null: false
    t.integer "conversation_priority", default: 0, null: false
    t.integer "fair_distribution_limit", default: 100, null: false
    t.integer "fair_distribution_window", default: 3600, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "exclude_older_than_hours", default: 168
    t.index ["account_id", "name"], name: "index_assignment_policies_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_assignment_policies_on_account_id"
    t.index ["enabled"], name: "index_assignment_policies_on_enabled"
  end

  create_table "attachments", id: :serial, force: :cascade do |t|
    t.integer "file_type", default: 0
    t.string "external_url"
    t.float "coordinates_lat", default: 0.0
    t.float "coordinates_long", default: 0.0
    t.integer "message_id", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "fallback_title"
    t.string "extension"
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_attachments_on_account_id"
    t.index ["message_id"], name: "index_attachments_on_message_id"
  end

  create_table "audits", force: :cascade do |t|
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.bigint "associated_id"
    t.string "associated_type"
    t.bigint "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.jsonb "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at", precision: nil
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "automation_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "event_name", null: false
    t.jsonb "conditions", default: "{}", null: false
    t.jsonb "actions", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.index ["account_id"], name: "index_automation_rules_on_account_id"
  end

  create_table "calls", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "message_id"
    t.bigint "accepted_by_agent_id"
    t.string "provider_call_id", null: false
    t.integer "provider", default: 0, null: false
    t.integer "direction", null: false
    t.string "status", default: "ringing", null: false
    t.datetime "started_at"
    t.integer "duration_seconds"
    t.string "end_reason"
    t.jsonb "meta", default: {}
    t.text "transcript"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "contact_id"], name: "index_calls_on_account_id_and_contact_id"
    t.index ["account_id", "conversation_id"], name: "index_calls_on_account_id_and_conversation_id"
    t.index ["account_id", "created_at"], name: "index_calls_on_account_id_and_created_at"
    t.index ["message_id"], name: "index_calls_on_message_id"
    t.index ["provider", "provider_call_id"], name: "index_calls_on_provider_and_provider_call_id", unique: true
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "display_id", null: false
    t.string "title", null: false
    t.text "description"
    t.text "message", null: false
    t.integer "sender_id"
    t.boolean "enabled", default: true
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.jsonb "trigger_rules", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "campaign_type", default: 0, null: false
    t.integer "campaign_status", default: 0, null: false
    t.jsonb "audience", default: []
    t.datetime "scheduled_at", precision: nil
    t.boolean "trigger_only_during_business_hours", default: false
    t.jsonb "template_params"
    t.index ["account_id"], name: "index_campaigns_on_account_id"
    t.index ["campaign_status"], name: "index_campaigns_on_campaign_status"
    t.index ["campaign_type"], name: "index_campaigns_on_campaign_type"
    t.index ["inbox_id"], name: "index_campaigns_on_inbox_id"
    t.index ["scheduled_at"], name: "index_campaigns_on_scheduled_at"
  end

  create_table "canned_responses", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "short_code"
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "categories", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.string "name"
    t.text "description"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale", default: "en"
    t.string "slug", null: false
    t.bigint "parent_category_id"
    t.bigint "associated_category_id"
    t.string "icon", default: ""
    t.string "icon_color", default: ""
    t.index ["associated_category_id"], name: "index_categories_on_associated_category_id"
    t.index ["locale", "account_id"], name: "index_categories_on_locale_and_account_id"
    t.index ["locale"], name: "index_categories_on_locale"
    t.index ["parent_category_id"], name: "index_categories_on_parent_category_id"
    t.index ["slug", "locale", "portal_id"], name: "index_categories_on_slug_and_locale_and_portal_id", unique: true
  end

  create_table "channel_api", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "webhook_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "identifier"
    t.string "hmac_token"
    t.boolean "hmac_mandatory", default: false
    t.jsonb "additional_attributes", default: {}
    t.string "secret"
    t.index ["hmac_token"], name: "index_channel_api_on_hmac_token", unique: true
    t.index ["identifier"], name: "index_channel_api_on_identifier", unique: true
  end

  create_table "channel_email", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "email", null: false
    t.string "forward_to_email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "imap_enabled", default: false
    t.string "imap_address", default: ""
    t.integer "imap_port", default: 0
    t.string "imap_login", default: ""
    t.string "imap_password", default: ""
    t.boolean "imap_enable_ssl", default: true
    t.boolean "smtp_enabled", default: false
    t.string "smtp_address", default: ""
    t.integer "smtp_port", default: 0
    t.string "smtp_login", default: ""
    t.string "smtp_password", default: ""
    t.string "smtp_domain", default: ""
    t.boolean "smtp_enable_starttls_auto", default: true
    t.string "smtp_authentication", default: "login"
    t.string "smtp_openssl_verify_mode", default: "none"
    t.boolean "smtp_enable_ssl_tls", default: false
    t.jsonb "provider_config", default: {}
    t.string "provider"
    t.boolean "verified_for_sending", default: false, null: false
    t.string "imap_authentication", default: "plain"
    t.index ["email"], name: "index_channel_email_on_email", unique: true
    t.index ["forward_to_email"], name: "index_channel_email_on_forward_to_email", unique: true
  end

  create_table "channel_facebook_pages", id: :serial, force: :cascade do |t|
    t.string "page_id", null: false
    t.string "user_access_token", null: false
    t.string "page_access_token", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "instagram_id"
    t.index ["page_id", "account_id"], name: "index_channel_facebook_pages_on_page_id_and_account_id", unique: true
    t.index ["page_id"], name: "index_channel_facebook_pages_on_page_id"
  end

  create_table "channel_instagram", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.integer "account_id", null: false
    t.string "instagram_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instagram_id"], name: "index_channel_instagram_on_instagram_id", unique: true
  end

  create_table "channel_line", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "line_channel_id", null: false
    t.string "line_channel_secret", null: false
    t.string "line_channel_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["line_channel_id"], name: "index_channel_line_on_line_channel_id", unique: true
  end

  create_table "channel_sms", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["phone_number"], name: "index_channel_sms_on_phone_number", unique: true
  end

  create_table "channel_telegram", force: :cascade do |t|
    t.string "bot_name"
    t.integer "account_id", null: false
    t.string "bot_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bot_token"], name: "index_channel_telegram_on_bot_token", unique: true
  end

  create_table "channel_tiktok", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "business_id", null: false
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.string "refresh_token", null: false
    t.datetime "refresh_token_expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_channel_tiktok_on_business_id", unique: true
  end

  create_table "channel_twilio_sms", force: :cascade do |t|
    t.string "phone_number"
    t.string "auth_token", null: false
    t.string "account_sid", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "medium", default: 0
    t.string "messaging_service_sid"
    t.string "api_key_sid"
    t.jsonb "content_templates", default: {}
    t.datetime "content_templates_last_updated"
    t.boolean "voice_enabled", default: false, null: false
    t.string "twiml_app_sid"
    t.string "api_key_secret"
    t.jsonb "provider_config", default: {}
    t.index ["account_sid", "phone_number"], name: "index_channel_twilio_sms_on_account_sid_and_phone_number", unique: true
    t.index ["messaging_service_sid"], name: "index_channel_twilio_sms_on_messaging_service_sid", unique: true
    t.index ["phone_number"], name: "index_channel_twilio_sms_on_phone_number", unique: true
  end

  create_table "channel_twitter_profiles", force: :cascade do |t|
    t.string "profile_id", null: false
    t.string "twitter_access_token", null: false
    t.string "twitter_access_token_secret", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "tweets_enabled", default: true
    t.index ["account_id", "profile_id"], name: "index_channel_twitter_profiles_on_account_id_and_profile_id", unique: true
  end

  create_table "channel_web_widgets", id: :serial, force: :cascade do |t|
    t.string "website_url"
    t.integer "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "website_token"
    t.string "widget_color", default: "#1f93ff"
    t.string "welcome_title"
    t.string "welcome_tagline"
    t.integer "feature_flags", default: 7, null: false
    t.integer "reply_time", default: 0
    t.string "hmac_token"
    t.boolean "pre_chat_form_enabled", default: false
    t.jsonb "pre_chat_form_options", default: {}
    t.boolean "hmac_mandatory", default: false
    t.boolean "continuity_via_email", default: true, null: false
    t.text "allowed_domains", default: ""
    t.index ["hmac_token"], name: "index_channel_web_widgets_on_hmac_token", unique: true
    t.index ["website_token"], name: "index_channel_web_widgets_on_website_token", unique: true
  end

  create_table "channel_whatsapp", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "message_templates", default: {}
    t.datetime "message_templates_last_updated", precision: nil
    t.jsonb "phone_number_health", default: {}, null: false
    t.datetime "phone_number_health_checked_at"
    t.string "phone_number_health_error", limit: 500
    t.index ["phone_number"], name: "index_channel_whatsapp_on_phone_number", unique: true
    t.index ["phone_number_health_checked_at"], name: "index_channel_whatsapp_on_phone_number_health_checked_at"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "domain"
    t.text "description"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "contacts_count"
    t.jsonb "additional_attributes", default: {}
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.index ["account_id", "domain"], name: "index_companies_on_account_and_domain", unique: true, where: "(domain IS NOT NULL)"
    t.index ["account_id"], name: "index_companies_on_account_id"
    t.index ["name", "account_id"], name: "index_companies_on_name_and_account_id"
  end

  create_table "contact_inboxes", force: :cascade do |t|
    t.bigint "contact_id"
    t.bigint "inbox_id"
    t.text "source_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "hmac_verified", default: false
    t.string "pubsub_token"
    t.index ["contact_id"], name: "index_contact_inboxes_on_contact_id"
    t.index ["inbox_id", "source_id"], name: "index_contact_inboxes_on_inbox_id_and_source_id", unique: true
    t.index ["inbox_id"], name: "index_contact_inboxes_on_inbox_id"
    t.index ["pubsub_token"], name: "index_contact_inboxes_on_pubsub_token", unique: true
    t.index ["source_id"], name: "index_contact_inboxes_on_source_id"
  end

  create_table "contacts", id: :serial, force: :cascade do |t|
    t.string "name", default: ""
    t.string "email"
    t.string "phone_number"
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "additional_attributes", default: {}
    t.string "identifier"
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.integer "contact_type", default: 0
    t.string "middle_name", default: ""
    t.string "last_name", default: ""
    t.string "location", default: ""
    t.string "country_code", default: ""
    t.boolean "blocked", default: false, null: false
    t.bigint "company_id"
    t.string "phone_country_code_jabvox"
    t.string "phone_national_jabvox"
    t.bigint "jabvox_campaign_id"
    t.bigint "jabvox_affiliate_id"
    t.bigint "assignee_id"
    t.boolean "is_sold_jabvox", default: false, null: false
    t.jsonb "custom_fields_jabvox", default: {}, null: false
    t.string "lifecycle_stage_jabvox", default: "prospecto", null: false
    t.datetime "became_lead_at_jabvox"
    t.index "lower((email)::text), account_id", name: "index_contacts_on_lower_email_account_id"
    t.index ["account_id", "contact_type"], name: "index_contacts_on_account_id_and_contact_type"
    t.index ["account_id", "email", "phone_number", "identifier"], name: "index_contacts_on_nonempty_fields", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["account_id", "jabvox_affiliate_id"], name: "index_contacts_on_account_id_and_jabvox_affiliate_id"
    t.index ["account_id", "jabvox_campaign_id"], name: "index_contacts_on_account_id_and_jabvox_campaign_id"
    t.index ["account_id", "last_activity_at"], name: "index_contacts_on_account_id_and_last_activity_at", order: { last_activity_at: "DESC NULLS LAST" }
    t.index ["account_id", "lifecycle_stage_jabvox"], name: "index_contacts_on_account_id_and_lifecycle_stage_jabvox"
    t.index ["account_id"], name: "index_contacts_on_account_id"
    t.index ["account_id"], name: "index_resolved_contact_account_id", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["assignee_id"], name: "index_contacts_on_assignee_id"
    t.index ["blocked"], name: "index_contacts_on_blocked"
    t.index ["company_id"], name: "index_contacts_on_company_id"
    t.index ["custom_fields_jabvox"], name: "index_contacts_on_custom_fields_jabvox", using: :gin
    t.index ["email", "account_id"], name: "uniq_email_per_account_contact", unique: true
    t.index ["identifier", "account_id"], name: "uniq_identifier_per_account_contact", unique: true
    t.index ["is_sold_jabvox"], name: "index_contacts_on_is_sold_jabvox"
    t.index ["name", "email", "phone_number", "identifier"], name: "index_contacts_on_name_email_phone_number_identifier", opclass: :gin_trgm_ops, using: :gin
    t.index ["phone_number", "account_id"], name: "index_contacts_on_phone_number_and_account_id"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_conversation_participants_on_account_id"
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_conversation_participants_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversations", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "assignee_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "contact_id"
    t.integer "display_id", null: false
    t.datetime "contact_last_seen_at", precision: nil
    t.datetime "agent_last_seen_at", precision: nil
    t.jsonb "additional_attributes", default: {}
    t.bigint "contact_inbox_id"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "identifier"
    t.datetime "last_activity_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "team_id"
    t.bigint "campaign_id"
    t.datetime "snoozed_until", precision: nil
    t.jsonb "custom_attributes", default: {}
    t.datetime "assignee_last_seen_at", precision: nil
    t.datetime "first_reply_created_at", precision: nil
    t.integer "priority"
    t.bigint "sla_policy_id"
    t.datetime "waiting_since"
    t.text "cached_label_list"
    t.bigint "assignee_agent_bot_id"
    t.index ["account_id", "display_id"], name: "index_conversations_on_account_id_and_display_id", unique: true
    t.index ["account_id", "id"], name: "index_conversations_on_id_and_account_id"
    t.index ["account_id", "inbox_id", "status", "assignee_id"], name: "conv_acid_inbid_stat_asgnid_idx"
    t.index ["account_id"], name: "index_conversations_on_account_id"
    t.index ["assignee_id", "account_id"], name: "index_conversations_on_assignee_id_and_account_id"
    t.index ["campaign_id"], name: "index_conversations_on_campaign_id"
    t.index ["contact_id"], name: "index_conversations_on_contact_id"
    t.index ["contact_inbox_id"], name: "index_conversations_on_contact_inbox_id"
    t.index ["first_reply_created_at"], name: "index_conversations_on_first_reply_created_at"
    t.index ["identifier", "account_id"], name: "index_conversations_on_identifier_and_account_id"
    t.index ["inbox_id"], name: "index_conversations_on_inbox_id"
    t.index ["priority"], name: "index_conversations_on_priority"
    t.index ["status", "account_id"], name: "index_conversations_on_status_and_account_id"
    t.index ["status", "priority"], name: "index_conversations_on_status_and_priority"
    t.index ["team_id"], name: "index_conversations_on_team_id"
    t.index ["uuid"], name: "index_conversations_on_uuid", unique: true
    t.index ["waiting_since"], name: "index_conversations_on_waiting_since"
  end

  create_table "csat_survey_responses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "message_id", null: false
    t.integer "rating", null: false
    t.text "feedback_message"
    t.bigint "contact_id", null: false
    t.bigint "assigned_agent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "csat_review_notes"
    t.datetime "review_notes_updated_at"
    t.bigint "review_notes_updated_by_id"
    t.index ["account_id"], name: "index_csat_survey_responses_on_account_id"
    t.index ["assigned_agent_id"], name: "index_csat_survey_responses_on_assigned_agent_id"
    t.index ["contact_id"], name: "index_csat_survey_responses_on_contact_id"
    t.index ["conversation_id"], name: "index_csat_survey_responses_on_conversation_id"
    t.index ["message_id"], name: "index_csat_survey_responses_on_message_id", unique: true
    t.index ["review_notes_updated_by_id"], name: "index_csat_survey_responses_on_review_notes_updated_by_id"
  end

  create_table "custom_attribute_definitions", force: :cascade do |t|
    t.string "attribute_display_name"
    t.string "attribute_key"
    t.integer "attribute_display_type", default: 0
    t.integer "default_value"
    t.integer "attribute_model", default: 0
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "attribute_description"
    t.jsonb "attribute_values", default: []
    t.string "regex_pattern"
    t.string "regex_cue"
    t.index ["account_id"], name: "index_custom_attribute_definitions_on_account_id"
    t.index ["attribute_key", "attribute_model", "account_id"], name: "attribute_key_model_index", unique: true
  end

  create_table "custom_filters", force: :cascade do |t|
    t.string "name", null: false
    t.integer "filter_type", default: 0, null: false
    t.jsonb "query", default: "{}", null: false
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_filters_on_account_id"
    t.index ["user_id"], name: "index_custom_filters_on_user_id"
  end

  create_table "custom_roles", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.bigint "account_id", null: false
    t.text "permissions", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_roles_on_account_id"
  end

  create_table "dashboard_apps", force: :cascade do |t|
    t.string "title", null: false
    t.jsonb "content", default: []
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_dashboard_apps_on_account_id"
    t.index ["user_id"], name: "index_dashboard_apps_on_user_id"
  end

  create_table "data_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "data_type", null: false
    t.integer "status", default: 0, null: false
    t.text "processing_errors"
    t.integer "total_records"
    t.integer "processed_records"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.string "source_type"
    t.string "source_provider"
    t.jsonb "import_types", default: [], null: false
    t.integer "initiated_by_id"
    t.text "access_token"
    t.jsonb "source_metadata", default: {}, null: false
    t.jsonb "stats", default: {}, null: false
    t.jsonb "cursor", default: {}, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "abandoned_at"
    t.datetime "last_error_at"
    t.index ["account_id"], name: "index_data_imports_on_account_id"
    t.index ["initiated_by_id"], name: "index_data_imports_on_initiated_by_id"
    t.index ["source_provider"], name: "index_data_imports_on_source_provider"
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "body", null: false
    t.integer "account_id"
    t.integer "template_type", default: 1
    t.integer "locale", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "inbox_id"
    t.index ["account_id", "name", "template_type", "locale"], name: "index_email_templates_on_account_scope", unique: true, where: "((account_id IS NOT NULL) AND (inbox_id IS NULL))"
    t.index ["inbox_id", "name", "template_type", "locale"], name: "index_email_templates_on_inbox_scope", unique: true, where: "(inbox_id IS NOT NULL)"
    t.index ["inbox_id"], name: "index_email_templates_on_inbox_id"
    t.index ["name", "template_type", "locale"], name: "index_email_templates_on_installation_scope", unique: true, where: "((account_id IS NULL) AND (inbox_id IS NULL))"
  end

  create_table "folders", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "category_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "inbox_assignment_policies", force: :cascade do |t|
    t.bigint "inbox_id", null: false
    t.bigint "assignment_policy_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_policy_id"], name: "index_inbox_assignment_policies_on_assignment_policy_id"
    t.index ["inbox_id"], name: "index_inbox_assignment_policies_on_inbox_id", unique: true
  end

  create_table "inbox_capacity_limits", force: :cascade do |t|
    t.bigint "agent_capacity_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "conversation_limit", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_capacity_policy_id", "inbox_id"], name: "idx_on_agent_capacity_policy_id_inbox_id_71c7ec4caf", unique: true
    t.index ["agent_capacity_policy_id"], name: "index_inbox_capacity_limits_on_agent_capacity_policy_id"
    t.index ["inbox_id"], name: "index_inbox_capacity_limits_on_inbox_id"
  end

  create_table "inbox_members", id: :serial, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "inbox_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["inbox_id", "user_id"], name: "index_inbox_members_on_inbox_id_and_user_id", unique: true
    t.index ["inbox_id"], name: "index_inbox_members_on_inbox_id"
  end

  create_table "inboxes", id: :serial, force: :cascade do |t|
    t.integer "channel_id", null: false
    t.integer "account_id", null: false
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "channel_type"
    t.boolean "enable_auto_assignment", default: true
    t.boolean "greeting_enabled", default: false
    t.string "greeting_message"
    t.string "email_address"
    t.boolean "working_hours_enabled", default: false
    t.string "out_of_office_message"
    t.string "timezone", default: "UTC"
    t.boolean "enable_email_collect", default: true
    t.boolean "csat_survey_enabled", default: false
    t.boolean "allow_messages_after_resolved", default: true
    t.jsonb "auto_assignment_config", default: {}
    t.boolean "lock_to_single_conversation", default: false, null: false
    t.bigint "portal_id"
    t.integer "sender_name_type", default: 0, null: false
    t.string "business_name"
    t.jsonb "csat_config", default: {}, null: false
    t.index ["account_id"], name: "index_inboxes_on_account_id"
    t.index ["channel_id", "channel_type"], name: "index_inboxes_on_channel_id_and_channel_type"
    t.index ["portal_id"], name: "index_inboxes_on_portal_id"
  end

  create_table "installation_configs", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "serialized_value", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "locked", default: true, null: false
    t.index ["name", "created_at"], name: "index_installation_configs_on_name_and_created_at", unique: true
    t.index ["name"], name: "index_installation_configs_on_name", unique: true
  end

  create_table "integrations_hooks", force: :cascade do |t|
    t.integer "status", default: 1
    t.integer "inbox_id"
    t.integer "account_id"
    t.string "app_id"
    t.integer "hook_type", default: 0
    t.string "reference_id"
    t.string "access_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "settings", default: {}
  end

  create_table "jabvox_affiliate_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_affiliate_id", null: false
    t.string "filename"
    t.integer "rows_total", default: 0, null: false
    t.integer "rows_ok", default: 0, null: false
    t.integer "rows_failed", default: 0, null: false
    t.integer "import_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.integer "rows_duplicated", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "country_jabvox", default: "", null: false
    t.string "campaign_name_jabvox"
    t.string "error_message"
    t.datetime "completed_at"
    t.index ["account_id"], name: "index_jabvox_affiliate_imports_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_affiliate_imports_on_created_by_id"
    t.index ["jabvox_affiliate_id", "created_at"], name: "index_jabvox_affiliate_imports_on_affiliate_and_created"
    t.index ["jabvox_affiliate_id"], name: "index_jabvox_affiliate_imports_on_jabvox_affiliate_id"
  end

  create_table "jabvox_affiliate_ip_whitelists", force: :cascade do |t|
    t.bigint "jabvox_affiliate_id", null: false
    t.string "ip", limit: 45, null: false
    t.boolean "is_active", default: true, null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jabvox_affiliate_id", "ip"], name: "idx_affiliate_ip_whitelists_on_affiliate_and_ip", unique: true
    t.index ["jabvox_affiliate_id"], name: "index_jabvox_affiliate_ip_whitelists_on_jabvox_affiliate_id"
  end

  create_table "jabvox_affiliates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "account_code", null: false
    t.string "auth_token", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "portal_slug", null: false
    t.boolean "owned_jabvox", default: false, null: false
    t.index ["account_code"], name: "index_jabvox_affiliates_on_account_code", unique: true
    t.index ["account_id", "active"], name: "index_jabvox_affiliates_on_account_id_and_active"
    t.index ["account_id"], name: "index_jabvox_affiliates_on_account_id"
    t.index ["account_id"], name: "index_jabvox_affiliates_one_owned_per_account", unique: true, where: "(owned_jabvox = true)"
    t.index ["auth_token"], name: "index_jabvox_affiliates_on_auth_token", unique: true
    t.index ["portal_slug"], name: "index_jabvox_affiliates_on_portal_slug", unique: true
  end

  create_table "jabvox_agent_availabilities", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.integer "day_of_week", null: false
    t.integer "start_minute", null: false
    t.integer "end_minute", null: false
    t.integer "slot_minutes", default: 30, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "branch_id"
    t.index ["account_id", "branch_id", "user_id", "day_of_week"], name: "index_jabvox_availabilities_lookup"
    t.index ["account_id"], name: "index_jabvox_agent_availabilities_on_account_id"
    t.index ["branch_id"], name: "index_jabvox_agent_availabilities_on_branch_id"
    t.index ["user_id"], name: "index_jabvox_agent_availabilities_on_user_id"
  end

  create_table "jabvox_ai_balance_movements", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "kind_jabvox", null: false
    t.integer "amount_cents_jabvox", default: 0, null: false
    t.integer "plan_budget_cents_after_jabvox"
    t.integer "purchased_budget_cents_after_jabvox"
    t.bigint "jabvox_plan_id"
    t.string "reference_jabvox"
    t.string "idempotency_key_jabvox"
    t.jsonb "metadata_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["account_id", "created_at"], name: "idx_ai_balance_movements_account"
    t.index ["account_id"], name: "index_jabvox_ai_balance_movements_on_account_id"
    t.index ["idempotency_key_jabvox"], name: "idx_ai_balance_movements_idem", unique: true, where: "(idempotency_key_jabvox IS NOT NULL)"
  end

  create_table "jabvox_ai_chat_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "bucket_url_jabvox", limit: 500
    t.string "bucket_access_key_jabvox", limit: 200
    t.text "bucket_secret_key_jabvox"
    t.string "bucket_region_jabvox", limit: 50, default: "us-east-1"
    t.string "bucket_name_jabvox", limit: 200
    t.boolean "web_search_enabled_jabvox", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "documents_storage_jabvox_id"
    t.index ["account_id"], name: "index_jabvox_ai_chat_configs_on_account_id", unique: true
    t.index ["documents_storage_jabvox_id"], name: "index_jabvox_ai_chat_configs_on_documents_storage_jabvox_id"
  end

  create_table "jabvox_ai_chat_documents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", limit: 300, null: false
    t.string "s3_key_jabvox", limit: 500, null: false
    t.string "content_type_jabvox", limit: 100
    t.bigint "size_jabvox", default: 0
    t.boolean "is_enabled_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "s3_key_jabvox"], name: "idx_jabvox_ai_chat_docs_key", unique: true
    t.index ["account_id"], name: "index_jabvox_ai_chat_documents_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_ai_chat_documents_on_created_by_id"
  end

  create_table "jabvox_ai_chat_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "session_id_jabvox", limit: 100, null: false
    t.string "role_jabvox", limit: 20, null: false
    t.text "content_jabvox", null: false
    t.jsonb "metadata_jabvox", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status_jabvox"
    t.index ["account_id", "user_id", "session_id_jabvox"], name: "idx_jabvox_ai_chat_messages_session"
    t.index ["account_id", "user_id"], name: "idx_jabvox_ai_chat_messages_user"
    t.index ["account_id"], name: "index_jabvox_ai_chat_messages_on_account_id"
    t.index ["session_id_jabvox", "status_jabvox"], name: "idx_jabvox_ai_chat_on_session_status"
    t.index ["user_id"], name: "index_jabvox_ai_chat_messages_on_user_id"
  end

  create_table "jabvox_ai_chat_models", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", limit: 150, null: false
    t.string "provider_jabvox", limit: 50, null: false
    t.string "model_jabvox", limit: 200, null: false
    t.text "api_key_jabvox"
    t.string "base_url_jabvox", limit: 500
    t.boolean "is_default_jabvox", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source_jabvox", default: "local", null: false
    t.string "hermes_model_id_jabvox"
    t.bigint "hermes_agent_id"
    t.index ["account_id"], name: "index_jabvox_ai_chat_models_on_account_id"
    t.index ["hermes_agent_id"], name: "index_jabvox_ai_chat_models_on_hermes_agent_id"
  end

  create_table "jabvox_ai_chat_sessions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "session_id_jabvox", limit: 100, null: false
    t.string "title_jabvox"
    t.bigint "connection_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id", "session_id_jabvox"], name: "idx_jabvox_ai_chat_sessions_uniq", unique: true
    t.index ["account_id"], name: "index_jabvox_ai_chat_sessions_on_account_id"
    t.index ["user_id"], name: "index_jabvox_ai_chat_sessions_on_user_id"
  end

  create_table "jabvox_ai_chat_storages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "bucket_name", default: "", null: false
    t.string "bucket_region", default: "us-east-1", null: false
    t.string "endpoint", default: "", null: false
    t.string "access_key", default: "", null: false
    t.text "secret_key"
    t.string "path_prefix", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_ai_chat_storages_on_account_id"
  end

  create_table "jabvox_ai_chat_user_permissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.boolean "can_use_jabvox", default: true, null: false
    t.boolean "can_use_models_jabvox", default: true, null: false
    t.boolean "can_use_documents_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "idx_jabvox_ai_chat_permissions_unique", unique: true
  end

  create_table "jabvox_ai_provider_accounts", force: :cascade do |t|
    t.bigint "account_id"
    t.string "team_id_jabvox"
    t.integer "plan_budget_cents_jabvox", default: 0, null: false
    t.integer "purchased_budget_cents_jabvox", default: 0, null: false
    t.decimal "cached_spend_jabvox", precision: 15, scale: 6
    t.datetime "spend_updated_at_jabvox"
    t.string "last_reset_period_jabvox"
    t.string "status_jabvox", default: "active", null: false
    t.datetime "synced_at_jabvox"
    t.string "last_error_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "team_alias_jabvox"
    t.decimal "remote_max_budget_jabvox", precision: 15, scale: 6
    t.boolean "remote_blocked_jabvox", default: false, null: false
    t.jsonb "remote_models_jabvox", default: [], null: false
    t.string "origin_jabvox", default: "jabvox", null: false
    t.index ["account_id"], name: "idx_ai_provider_accounts_account", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["team_id_jabvox"], name: "idx_ai_provider_accounts_team", unique: true, where: "((team_id_jabvox IS NOT NULL) AND ((team_id_jabvox)::text <> ''::text))"
  end

  create_table "jabvox_ai_provider_configs", force: :cascade do |t|
    t.string "provider_name_jabvox", default: "Proveedor IA", null: false
    t.string "base_url_jabvox"
    t.text "master_key_jabvox"
    t.boolean "enabled_jabvox", default: false, null: false
    t.string "status_jabvox", default: "disconnected", null: false
    t.datetime "last_check_at_jabvox"
    t.string "last_error_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "jabvox_analytics_audit_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "action_jabvox", null: false
    t.string "auditable_type_jabvox"
    t.bigint "auditable_id_jabvox"
    t.string "result_jabvox", null: false
    t.string "ip_address_jabvox"
    t.string "user_agent_jabvox"
    t.jsonb "metadata_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["account_id", "action_jabvox"], name: "idx_on_account_id_action_jabvox_a1695cd477"
    t.index ["account_id", "auditable_type_jabvox", "auditable_id_jabvox"], name: "idx_jabvox_analytics_audit_auditable"
    t.index ["account_id", "created_at"], name: "index_jabvox_analytics_audit_logs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_jabvox_analytics_audit_logs_on_account_id"
    t.index ["user_id"], name: "index_jabvox_analytics_audit_logs_on_user_id"
  end

  create_table "jabvox_analytics_cross_joins", force: :cascade do |t|
    t.bigint "cross_report_id", null: false
    t.bigint "left_source_id", null: false
    t.string "left_column_jabvox", null: false
    t.bigint "right_source_id", null: false
    t.string "right_column_jabvox", null: false
    t.string "join_type_jabvox", default: "inner", null: false
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cross_report_id"], name: "index_jabvox_analytics_cross_joins_on_cross_report_id"
    t.index ["left_source_id"], name: "index_jabvox_analytics_cross_joins_on_left_source_id"
    t.index ["right_source_id"], name: "index_jabvox_analytics_cross_joins_on_right_source_id"
  end

  create_table "jabvox_analytics_cross_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.integer "row_limit_jabvox", default: 1000, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_analytics_cross_reports_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_cross_reports_on_created_by_id"
  end

  create_table "jabvox_analytics_cross_sources", force: :cascade do |t|
    t.bigint "cross_report_id", null: false
    t.bigint "data_source_id", null: false
    t.string "table_jabvox", null: false
    t.string "alias_jabvox", null: false
    t.jsonb "columns_jabvox", default: [], null: false
    t.jsonb "filters_jabvox", default: [], null: false
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cross_report_id", "alias_jabvox"], name: "idx_cross_sources_report_alias", unique: true
    t.index ["cross_report_id"], name: "index_jabvox_analytics_cross_sources_on_cross_report_id"
    t.index ["data_source_id"], name: "index_jabvox_analytics_cross_sources_on_data_source_id"
  end

  create_table "jabvox_analytics_dashboard_widgets", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "dashboard_id", null: false
    t.bigint "data_source_id"
    t.string "widget_type_jabvox", null: false
    t.string "title_jabvox", default: "", null: false
    t.jsonb "query_spec_jabvox", default: {}, null: false
    t.text "custom_sql_jabvox"
    t.jsonb "config_jabvox", default: {}, null: false
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "dashboard_id"], name: "idx_on_account_id_dashboard_id_0dbd985dda"
    t.index ["account_id"], name: "index_jabvox_analytics_dashboard_widgets_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_dashboard_widgets_on_created_by_id"
    t.index ["dashboard_id"], name: "index_jabvox_analytics_dashboard_widgets_on_dashboard_id"
    t.index ["data_source_id"], name: "index_jabvox_analytics_dashboard_widgets_on_data_source_id"
  end

  create_table "jabvox_analytics_dashboards", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "folder_id"
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.jsonb "layout_jabvox", default: [], null: false
    t.jsonb "global_filters_jabvox", default: [], null: false
    t.integer "cache_ttl_seconds_jabvox", default: 300, null: false
    t.boolean "is_template_jabvox", default: false, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "folder_id"], name: "index_jabvox_analytics_dashboards_on_account_id_and_folder_id"
    t.index ["account_id"], name: "index_jabvox_analytics_dashboards_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_dashboards_on_created_by_id"
    t.index ["folder_id"], name: "index_jabvox_analytics_dashboards_on_folder_id"
  end

  create_table "jabvox_analytics_data_source_permissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "data_source_id", null: false
    t.bigint "user_id"
    t.bigint "role_id"
    t.boolean "can_query_jabvox", default: true, null: false
    t.boolean "can_use_custom_sql_jabvox", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_analytics_data_source_permissions_on_account_id"
    t.index ["data_source_id", "role_id"], name: "idx_jabvox_analytics_dsp_role", unique: true
    t.index ["data_source_id", "user_id"], name: "idx_jabvox_analytics_dsp_user", unique: true
    t.index ["data_source_id"], name: "idx_on_data_source_id_be7ed7447f"
    t.index ["role_id"], name: "index_jabvox_analytics_data_source_permissions_on_role_id"
    t.index ["user_id"], name: "index_jabvox_analytics_data_source_permissions_on_user_id"
  end

  create_table "jabvox_analytics_data_sources", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "engine_jabvox", null: false
    t.string "host_jabvox"
    t.integer "port_jabvox"
    t.string "database_jabvox"
    t.string "username_jabvox"
    t.text "password_jabvox"
    t.string "ssl_mode_jabvox", default: "prefer", null: false
    t.text "ssl_ca_jabvox"
    t.string "sqlite_path_jabvox"
    t.jsonb "options_jabvox", default: {}, null: false
    t.boolean "allow_private_network_jabvox", default: false, null: false
    t.integer "max_rows_jabvox", default: 1000, null: false
    t.integer "query_timeout_ms_jabvox", default: 30000, null: false
    t.string "status_jabvox", default: "untested", null: false
    t.datetime "last_tested_at_jabvox"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name_jabvox"], name: "idx_on_account_id_name_jabvox_14bc87f57e", unique: true
    t.index ["account_id"], name: "index_jabvox_analytics_data_sources_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_data_sources_on_created_by_id"
  end

  create_table "jabvox_analytics_exports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "dashboard_id"
    t.bigint "user_id", null: false
    t.string "format_jabvox", null: false
    t.string "status_jabvox", default: "pending", null: false
    t.string "file_url_jabvox"
    t.text "error_jabvox"
    t.jsonb "params_jabvox", default: {}, null: false
    t.datetime "expires_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status_jabvox"], name: "index_jabvox_analytics_exports_on_account_id_and_status_jabvox"
    t.index ["account_id"], name: "index_jabvox_analytics_exports_on_account_id"
    t.index ["dashboard_id"], name: "index_jabvox_analytics_exports_on_dashboard_id"
    t.index ["user_id"], name: "index_jabvox_analytics_exports_on_user_id"
  end

  create_table "jabvox_analytics_folders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.bigint "parent_id"
    t.integer "position_jabvox", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "parent_id"], name: "index_jabvox_analytics_folders_on_account_id_and_parent_id"
    t.index ["account_id"], name: "index_jabvox_analytics_folders_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_folders_on_created_by_id"
    t.index ["parent_id"], name: "index_jabvox_analytics_folders_on_parent_id"
  end

  create_table "jabvox_analytics_permissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "role_id", null: false
    t.string "permission_key_jabvox", null: false
    t.boolean "granted_jabvox", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "role_id", "permission_key_jabvox"], name: "idx_jabvox_analytics_perms_unique", unique: true
    t.index ["account_id"], name: "index_jabvox_analytics_permissions_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_permissions_on_created_by_id"
    t.index ["role_id"], name: "index_jabvox_analytics_permissions_on_role_id"
  end

  create_table "jabvox_analytics_query_cache", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "data_source_id"
    t.string "cache_key_jabvox", null: false
    t.jsonb "result_jabvox", default: {}, null: false
    t.integer "row_count_jabvox", default: 0, null: false
    t.datetime "expires_at_jabvox", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "cache_key_jabvox"], name: "idx_on_account_id_cache_key_jabvox_8c331ff9f1", unique: true
    t.index ["account_id"], name: "index_jabvox_analytics_query_cache_on_account_id"
    t.index ["data_source_id"], name: "index_jabvox_analytics_query_cache_on_data_source_id"
    t.index ["expires_at_jabvox"], name: "index_jabvox_analytics_query_cache_on_expires_at_jabvox"
  end

  create_table "jabvox_analytics_roles", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "slug_jabvox", null: false
    t.boolean "is_system_jabvox", default: false, null: false
    t.string "description_jabvox", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "slug_jabvox"], name: "index_jabvox_analytics_roles_on_account_id_and_slug_jabvox", unique: true
    t.index ["account_id"], name: "index_jabvox_analytics_roles_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_roles_on_created_by_id"
  end

  create_table "jabvox_analytics_shares", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "dashboard_id", null: false
    t.string "subject_type_jabvox", null: false
    t.bigint "subject_id_jabvox", null: false
    t.string "access_level_jabvox", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_analytics_shares_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_shares_on_created_by_id"
    t.index ["dashboard_id", "subject_type_jabvox", "subject_id_jabvox"], name: "idx_jabvox_analytics_shares_unique", unique: true
    t.index ["dashboard_id"], name: "index_jabvox_analytics_shares_on_dashboard_id"
  end

  create_table "jabvox_analytics_user_permissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "role_id"
    t.jsonb "overrides_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "idx_on_account_id_user_id_d329916899", unique: true
    t.index ["account_id"], name: "index_jabvox_analytics_user_permissions_on_account_id"
    t.index ["role_id"], name: "index_jabvox_analytics_user_permissions_on_role_id"
    t.index ["user_id"], name: "index_jabvox_analytics_user_permissions_on_user_id"
  end

  create_table "jabvox_analytics_widget_filters", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "dashboard_id"
    t.bigint "widget_id"
    t.string "field_jabvox", null: false
    t.string "operator_jabvox", null: false
    t.jsonb "value_jabvox", default: {}, null: false
    t.string "filter_type_jabvox", null: false
    t.boolean "is_global_jabvox", default: false, null: false
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "dashboard_id"], name: "idx_on_account_id_dashboard_id_9c660e1919"
    t.index ["account_id", "widget_id"], name: "idx_on_account_id_widget_id_9ad6238e06"
    t.index ["account_id"], name: "index_jabvox_analytics_widget_filters_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_analytics_widget_filters_on_created_by_id"
    t.index ["dashboard_id"], name: "index_jabvox_analytics_widget_filters_on_dashboard_id"
    t.index ["widget_id"], name: "index_jabvox_analytics_widget_filters_on_widget_id"
  end

  create_table "jabvox_app_state_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.integer "app_state_id"
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id", "started_at"], name: "idx_on_account_id_user_id_started_at_a0274f796f"
    t.index ["account_id"], name: "index_jabvox_app_state_logs_on_account_id"
    t.index ["user_id", "ended_at"], name: "index_jabvox_app_state_logs_on_user_id_and_ended_at"
  end

  create_table "jabvox_app_states", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "color", default: "#6b7280", null: false
    t.integer "position", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "position"], name: "index_jabvox_app_states_on_account_id_and_position"
    t.index ["account_id"], name: "index_jabvox_app_states_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_app_states_on_created_by_id"
  end

  create_table "jabvox_audio_advisors", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "external_id"
    t.bigint "user_id"
    t.boolean "active", default: true, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "external_id"], name: "index_audio_advisors_on_account_and_external_id", unique: true
    t.index ["account_id"], name: "index_jabvox_audio_advisors_on_account_id"
  end

  create_table "jabvox_audio_anatomy_criteria", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.text "description", default: "", null: false
    t.text "positive_signal", default: "", null: false
    t.text "opportunity_signal", default: "", null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_audio_anatomy_criteria_on_account_id"
  end

  create_table "jabvox_audio_assignments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "storage_id", null: false
    t.string "file_key", null: false
    t.bigint "typification_id"
    t.bigint "agent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_audio_assignments_on_account_id"
    t.index ["agent_id"], name: "index_jabvox_audio_assignments_on_agent_id"
    t.index ["created_by_id"], name: "index_jabvox_audio_assignments_on_created_by_id"
    t.index ["storage_id", "file_key"], name: "index_jabvox_audio_assignments_on_storage_id_and_file_key", unique: true
    t.index ["storage_id"], name: "index_jabvox_audio_assignments_on_storage_id"
    t.index ["typification_id"], name: "index_jabvox_audio_assignments_on_typification_id"
  end

  create_table "jabvox_audio_code_mappings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "kind", null: false
    t.string "code", null: false
    t.bigint "typification_id"
    t.bigint "advisor_id"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "kind", "code"], name: "index_audio_code_mappings_on_account_kind_code", unique: true
    t.index ["account_id"], name: "index_jabvox_audio_code_mappings_on_account_id"
  end

  create_table "jabvox_audio_filename_patterns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "pattern", null: false
    t.string "date_format", default: "%d-%m-%Y", null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_audio_filename_patterns_on_account_id"
  end

  create_table "jabvox_audio_infaltables", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "typification_id", null: false
    t.text "text", null: false
    t.integer "position", default: 0, null: false
    t.boolean "optional", default: false, null: false
    t.boolean "active", default: true, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "typification_id"], name: "index_audio_infaltables_on_account_and_typification"
    t.index ["account_id"], name: "index_jabvox_audio_infaltables_on_account_id"
  end

  create_table "jabvox_audio_jobs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "pipeline_id"
    t.bigint "storage_id"
    t.bigint "created_by_id"
    t.string "status", default: "pending", null: false
    t.integer "total_count", default: 0, null: false
    t.integer "processed_count", default: 0, null: false
    t.integer "passed_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.integer "positive_count", default: 0, null: false
    t.integer "neutral_count", default: 0, null: false
    t.integer "negative_count", default: 0, null: false
    t.integer "average_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "label_jabvox"
    t.index ["account_id", "label_jabvox"], name: "index_jabvox_audio_jobs_on_account_and_label"
    t.index ["account_id"], name: "index_jabvox_audio_jobs_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_audio_jobs_on_created_by_id"
    t.index ["pipeline_id"], name: "index_jabvox_audio_jobs_on_pipeline_id"
    t.index ["storage_id"], name: "index_jabvox_audio_jobs_on_storage_id"
  end

  create_table "jabvox_audio_permissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.boolean "can_access", default: false, null: false
    t.boolean "can_view_reports", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "index_jabvox_audio_permissions_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_jabvox_audio_permissions_on_account_id"
    t.index ["user_id"], name: "index_jabvox_audio_permissions_on_user_id"
  end

  create_table "jabvox_audio_pipelines", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.bigint "transcription_model_id"
    t.text "transcription_prompt"
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "typification_id"
    t.string "timestamp_mode_jabvox", default: "none", null: false
    t.integer "segment_seconds_jabvox", default: 30, null: false
    t.bigint "created_by_id"
    t.integer "review_threshold_jabvox", default: 60, null: false
    t.boolean "qa_mode_jabvox", default: false, null: false
    t.boolean "qa_reclassify_jabvox", default: true, null: false
    t.integer "qa_infaltables_weight_jabvox", default: 100, null: false
    t.integer "qa_anatomy_weight_jabvox", default: 0, null: false
    t.index ["account_id"], name: "index_jabvox_audio_pipelines_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_audio_pipelines_on_created_by_id"
    t.index ["transcription_model_id"], name: "index_jabvox_audio_pipelines_on_transcription_model_id"
    t.index ["typification_id"], name: "index_jabvox_audio_pipelines_on_typification_id"
  end

  create_table "jabvox_audio_results", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "account_id", null: false
    t.string "file_key", null: false
    t.text "transcript"
    t.integer "final_score"
    t.boolean "passed", default: false, null: false
    t.string "sentiment"
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.jsonb "stages_data", default: [], null: false
    t.integer "processing_time_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "assigned_agent_id"
    t.bigint "typification_id"
    t.jsonb "transcript_words_jabvox", default: [], null: false
    t.bigint "created_by_id"
    t.jsonb "infaltables_result", default: [], null: false
    t.jsonb "anatomy_result", default: [], null: false
    t.integer "infaltables_score"
    t.integer "infaltables_applicable"
    t.integer "infaltables_met"
    t.bigint "detected_typification_id"
    t.jsonb "qa_summary", default: {}, null: false
    t.string "review_status", default: "ok", null: false
    t.bigint "advisor_id"
    t.jsonb "parsed_metadata", default: {}, null: false
    t.text "retypification_reason"
    t.text "review_explanation"
    t.integer "first_pass_score"
    t.index ["account_id"], name: "index_jabvox_audio_results_on_account_id"
    t.index ["advisor_id"], name: "index_jabvox_audio_results_on_advisor_id"
    t.index ["assigned_agent_id"], name: "index_jabvox_audio_results_on_assigned_agent_id"
    t.index ["created_by_id"], name: "index_jabvox_audio_results_on_created_by_id"
    t.index ["detected_typification_id"], name: "index_jabvox_audio_results_on_detected_typification_id"
    t.index ["job_id", "file_key"], name: "index_jabvox_audio_results_on_job_id_and_file_key"
    t.index ["job_id"], name: "index_jabvox_audio_results_on_job_id"
    t.index ["review_status"], name: "index_jabvox_audio_results_on_review_status"
    t.index ["typification_id"], name: "index_jabvox_audio_results_on_typification_id"
  end

  create_table "jabvox_audio_stages", force: :cascade do |t|
    t.bigint "pipeline_id", null: false
    t.integer "position", default: 0, null: false
    t.string "name", null: false
    t.text "prompt", null: false
    t.bigint "llm_model_id"
    t.integer "min_score", default: 60, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["llm_model_id"], name: "index_jabvox_audio_stages_on_llm_model_id"
    t.index ["pipeline_id", "position"], name: "index_jabvox_audio_stages_on_pipeline_id_and_position"
    t.index ["pipeline_id"], name: "index_jabvox_audio_stages_on_pipeline_id"
  end

  create_table "jabvox_audio_storages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.boolean "use_documents_config", default: false, null: false
    t.string "bucket_name", default: "", null: false
    t.string "bucket_region", default: "us-east-1", null: false
    t.string "endpoint", default: "", null: false
    t.string "access_key", default: "", null: false
    t.text "secret_key"
    t.string "path_prefix", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_audio_storages_on_account_id"
  end

  create_table "jabvox_billing_configs", force: :cascade do |t|
    t.integer "unpaid_account_cleanup_days", default: 7, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "jabvox_branch_hours", force: :cascade do |t|
    t.bigint "branch_id", null: false
    t.integer "day_of_week", null: false
    t.integer "open_minute", null: false
    t.integer "close_minute", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "day_of_week"], name: "index_jabvox_branch_hours_on_branch_id_and_day_of_week"
  end

  create_table "jabvox_branch_managers", force: :cascade do |t|
    t.bigint "branch_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "user_id"], name: "index_jabvox_branch_managers_on_branch_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_jabvox_branch_managers_on_user_id"
  end

  create_table "jabvox_branches", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "timezone_jabvox", default: "UTC", null: false
    t.string "color_jabvox", default: "#6366F1", null: false
    t.text "address_jabvox"
    t.boolean "active_jabvox", default: true, null: false
    t.integer "position_jabvox", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_branches_on_account_id_and_name_jabvox", unique: true
    t.index ["account_id"], name: "index_jabvox_branches_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_branches_on_created_by_id"
  end

  create_table "jabvox_bulk_whatsapp_batches", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id"
    t.bigint "sender_user_id"
    t.bigint "created_by_id"
    t.integer "total_rows_jabvox", default: 0, null: false
    t.integer "valid_rows_jabvox", default: 0, null: false
    t.string "status_jabvox", default: "pending", null: false
    t.text "error_jabvox"
    t.string "file_name_jabvox", default: "", null: false
    t.datetime "sent_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "access_token_id_jabvox"
    t.datetime "token_expires_at_jabvox"
    t.string "mode_jabvox", default: "template", null: false
    t.string "response_email_jabvox", default: "", null: false
    t.jsonb "payload_jabvox", default: {}, null: false
    t.integer "attempts_jabvox", default: 0, null: false
    t.uuid "batch_uuid_jabvox"
    t.string "callback_token_jabvox"
    t.string "source_type_jabvox"
    t.string "template_name_jabvox"
    t.string "template_language_jabvox"
    t.string "template_category_jabvox"
    t.jsonb "variable_mapping_jabvox", default: {}, null: false
    t.jsonb "filters_jabvox", default: {}, null: false
    t.integer "sent_count_jabvox", default: 0, null: false
    t.integer "failed_count_jabvox", default: 0, null: false
    t.bigint "source_batch_id_jabvox"
    t.datetime "finished_at_jabvox"
    t.index ["account_id", "created_at"], name: "idx_on_account_id_created_at_793a6e41e6"
    t.index ["account_id", "status_jabvox"], name: "idx_on_account_id_status_jabvox_8e3a4a349f"
    t.index ["account_id"], name: "index_jabvox_bulk_whatsapp_batches_on_account_id"
    t.index ["batch_uuid_jabvox"], name: "idx_bulk_wa_batches_uuid", unique: true
    t.index ["created_by_id"], name: "index_jabvox_bulk_whatsapp_batches_on_created_by_id"
    t.index ["inbox_id"], name: "index_jabvox_bulk_whatsapp_batches_on_inbox_id"
    t.index ["sender_user_id"], name: "index_jabvox_bulk_whatsapp_batches_on_sender_user_id"
    t.index ["source_batch_id_jabvox"], name: "idx_bulk_wa_batches_source_batch"
  end

  create_table "jabvox_bulk_whatsapp_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "webhook_url_jabvox", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "response_email_jabvox", default: "", null: false
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_bulk_whatsapp_configs_on_account_id", unique: true
    t.index ["created_by_id"], name: "index_jabvox_bulk_whatsapp_configs_on_created_by_id"
  end

  create_table "jabvox_bulk_whatsapp_recipients", force: :cascade do |t|
    t.bigint "bulk_whatsapp_batch_id", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id"
    t.string "lead_id_jabvox"
    t.string "name_jabvox", default: "", null: false
    t.string "phone_number_jabvox", default: "", null: false
    t.string "email_jabvox"
    t.string "template_name_jabvox"
    t.string "template_language_jabvox"
    t.jsonb "processed_params_jabvox", default: {}, null: false
    t.text "rendered_content_jabvox"
    t.string "status_jabvox", default: "pending", null: false
    t.bigint "conversation_id"
    t.bigint "chatwoot_message_id"
    t.string "error_code_jabvox"
    t.text "error_message_jabvox"
    t.datetime "sent_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bulk_whatsapp_batch_id", "status_jabvox"], name: "idx_bulk_wa_recipients_batch_status"
    t.index ["bulk_whatsapp_batch_id"], name: "idx_bulk_wa_recipients_batch"
    t.index ["chatwoot_message_id"], name: "idx_bulk_wa_recipients_message"
    t.index ["status_jabvox"], name: "idx_bulk_wa_recipients_status"
  end

  create_table "jabvox_calendar_event_participants", force: :cascade do |t|
    t.bigint "jabvox_calendar_event_id", null: false
    t.bigint "user_id"
    t.bigint "jabvox_calendar_external_person_id"
    t.text "note"
    t.integer "response_status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jabvox_calendar_event_id"], name: "idx_calendar_participants_on_event"
    t.index ["jabvox_calendar_external_person_id"], name: "idx_calendar_participants_on_external_person"
    t.index ["user_id"], name: "index_jabvox_calendar_event_participants_on_user_id"
  end

  create_table "jabvox_calendar_event_reminders", force: :cascade do |t|
    t.bigint "jabvox_calendar_event_id", null: false
    t.integer "minutes_before", null: false
    t.datetime "sent_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jabvox_calendar_event_id", "minutes_before"], name: "index_calendar_reminders_event_minutes", unique: true
    t.index ["jabvox_calendar_event_id"], name: "idx_on_jabvox_calendar_event_id_8c61b31913"
  end

  create_table "jabvox_calendar_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.datetime "start_at", null: false
    t.datetime "end_at", null: false
    t.boolean "all_day", default: false, null: false
    t.integer "event_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "color", default: "#3B82F6"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "contact_id"
    t.boolean "remind_before_day", default: false, null: false
    t.boolean "remind_before_hour", default: false, null: false
    t.string "recurrence_group_id"
    t.text "note"
    t.bigint "jabvox_task_id"
    t.bigint "branch_id"
    t.bigint "created_by_id"
    t.index ["account_id", "start_at"], name: "index_jabvox_calendar_events_on_account_id_and_start_at"
    t.index ["account_id", "user_id"], name: "index_jabvox_calendar_events_on_account_id_and_user_id"
    t.index ["account_id"], name: "index_jabvox_calendar_events_on_account_id"
    t.index ["branch_id"], name: "index_jabvox_calendar_events_on_branch_id"
    t.index ["contact_id"], name: "index_jabvox_calendar_events_on_contact_id"
    t.index ["created_by_id"], name: "index_jabvox_calendar_events_on_created_by_id"
    t.index ["jabvox_task_id"], name: "index_jabvox_calendar_events_on_jabvox_task_id"
    t.index ["recurrence_group_id"], name: "index_jabvox_calendar_events_on_recurrence_group_id"
    t.index ["user_id"], name: "index_jabvox_calendar_events_on_user_id"
  end

  create_table "jabvox_calendar_external_people", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "email"
    t.string "phone_number"
    t.text "notes"
    t.string "color", default: "#0EA5E9"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "email"], name: "index_jabvox_calendar_external_people_on_account_id_and_email"
    t.index ["account_id"], name: "index_jabvox_calendar_external_people_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_calendar_external_people_on_created_by_id"
  end

  create_table "jabvox_call_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "contact_id"
    t.bigint "conversation_id"
    t.bigint "typification_id"
    t.string "phone_number", default: "", null: false
    t.string "extension", default: "", null: false
    t.string "uniqueid"
    t.string "status", default: "calling", null: false
    t.text "note"
    t.datetime "called_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_call_logs_on_account_id"
    t.index ["contact_id"], name: "index_jabvox_call_logs_on_contact_id"
    t.index ["conversation_id"], name: "index_jabvox_call_logs_on_conversation_id"
    t.index ["typification_id"], name: "index_jabvox_call_logs_on_typification_id"
    t.index ["uniqueid"], name: "index_jabvox_call_logs_on_uniqueid"
    t.index ["user_id"], name: "index_jabvox_call_logs_on_user_id"
  end

  create_table "jabvox_campaigns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_campaigns_on_account_id_and_name_jabvox", unique: true
    t.index ["account_id"], name: "index_jabvox_campaigns_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_campaigns_on_created_by_id"
  end

  create_table "jabvox_cdr_call_analyses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "uniqueid", null: false
    t.bigint "pipeline_id"
    t.text "transcript"
    t.integer "final_score"
    t.boolean "passed", default: false, null: false
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.jsonb "stages_data", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "transcript_words_jabvox", default: [], null: false
    t.string "recording_file_jabvox"
    t.bigint "created_by_id"
    t.index ["account_id", "uniqueid"], name: "index_jabvox_cdr_call_analyses_on_account_id_and_uniqueid", unique: true
    t.index ["account_id"], name: "index_jabvox_cdr_call_analyses_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_cdr_call_analyses_on_created_by_id"
    t.index ["pipeline_id"], name: "index_jabvox_cdr_call_analyses_on_pipeline_id"
  end

  create_table "jabvox_cdr_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "mysql_host", default: "", null: false
    t.integer "mysql_port", default: 3306, null: false
    t.string "mysql_username", default: "", null: false
    t.text "mysql_password"
    t.string "mysql_database", default: "asteriskcdrdb", null: false
    t.string "mysql_table", default: "cdr", null: false
    t.string "ssh_host", default: "", null: false
    t.integer "ssh_port", default: 22, null: false
    t.string "ssh_username", default: "", null: false
    t.text "ssh_password"
    t.string "recordings_path", default: "/var/spool/asterisk/monitor", null: false
    t.string "analysis_mode", default: "manual", null: false
    t.integer "min_duration_seconds", default: 30, null: false
    t.bigint "default_pipeline_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_synced_calldate"
    t.string "last_synced_cursor"
    t.index ["account_id"], name: "idx_cdr_configs_configured", where: "((mysql_host)::text <> ''::text)"
    t.index ["account_id"], name: "index_jabvox_cdr_configs_on_account_id", unique: true
    t.index ["default_pipeline_id"], name: "index_jabvox_cdr_configs_on_default_pipeline_id"
  end

  create_table "jabvox_cdr_extension_mappings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "extension", null: false
    t.bigint "user_id"
    t.string "label", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "extension"], name: "idx_on_account_id_extension_8e86e57eba", unique: true
    t.index ["account_id"], name: "index_jabvox_cdr_extension_mappings_on_account_id"
    t.index ["user_id"], name: "index_jabvox_cdr_extension_mappings_on_user_id"
  end

  create_table "jabvox_cdr_pipelines", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.bigint "transcription_model_id"
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "typification_id"
    t.string "timestamp_mode_jabvox", default: "none", null: false
    t.integer "segment_seconds_jabvox", default: 30, null: false
    t.text "transcription_prompt"
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_cdr_pipelines_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_cdr_pipelines_on_created_by_id"
    t.index ["transcription_model_id"], name: "index_jabvox_cdr_pipelines_on_transcription_model_id"
    t.index ["typification_id"], name: "index_jabvox_cdr_pipelines_on_typification_id"
  end

  create_table "jabvox_cdr_records", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "uniqueid", null: false
    t.string "linkedid"
    t.datetime "calldate", null: false
    t.string "src"
    t.string "dst"
    t.string "channel"
    t.string "dstchannel"
    t.string "disposition"
    t.integer "duration", default: 0
    t.integer "billsec", default: 0
    t.string "recordingfile"
    t.string "origin"
    t.string "destination"
    t.string "origin_channel"
    t.string "agent_extension"
    t.string "medium"
    t.string "agent_name"
    t.bigint "typification_id"
    t.string "typification"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "agent_extension"], name: "idx_cdr_records_account_agent_ext"
    t.index ["account_id", "calldate", "id"], name: "idx_cdr_records_account_calldate_keyset", order: { calldate: :desc, id: :desc }
    t.index ["account_id", "calldate"], name: "idx_cdr_records_account_calldate"
    t.index ["account_id", "disposition"], name: "idx_cdr_records_account_disposition"
    t.index ["account_id", "medium"], name: "idx_cdr_records_account_medium"
    t.index ["account_id", "typification_id"], name: "idx_cdr_records_account_typ"
    t.index ["account_id", "uniqueid"], name: "idx_cdr_records_account_uniqueid", unique: true
    t.index ["account_id"], name: "index_jabvox_cdr_records_on_account_id"
  end

  create_table "jabvox_cdr_report_permissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.boolean "can_view", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "index_jabvox_cdr_report_permissions_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_jabvox_cdr_report_permissions_on_account_id"
    t.index ["user_id"], name: "index_jabvox_cdr_report_permissions_on_user_id"
  end

  create_table "jabvox_cdr_stages", force: :cascade do |t|
    t.bigint "pipeline_id", null: false
    t.integer "position", default: 0, null: false
    t.string "name", null: false
    t.text "prompt", null: false
    t.bigint "llm_model_id"
    t.integer "min_score", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["llm_model_id"], name: "index_jabvox_cdr_stages_on_llm_model_id"
    t.index ["pipeline_id", "position"], name: "index_jabvox_cdr_stages_on_pipeline_id_and_position"
    t.index ["pipeline_id"], name: "index_jabvox_cdr_stages_on_pipeline_id"
  end

  create_table "jabvox_cdr_sync_runs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.integer "duration_ms", default: 0
    t.boolean "pbx_reachable", default: false, null: false
    t.integer "inserted_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.integer "fetched_count", default: 0, null: false
    t.datetime "cursor_before"
    t.datetime "cursor_after"
    t.string "status", default: "ok", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "started_at"], name: "idx_cdr_sync_runs_account_started"
    t.index ["account_id"], name: "index_jabvox_cdr_sync_runs_on_account_id"
  end

  create_table "jabvox_context_forge_handoffs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "status", default: "pending", null: false
    t.string "contextforge_base_url"
    t.string "virtual_server_id"
    t.string "team_id"
    t.string "hermes_instance_id"
    t.text "scoped_token"
    t.jsonb "mcp_servers", default: [], null: false
    t.string "last_error"
    t.datetime "provisioned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "hermes_url"
    t.index ["account_id"], name: "index_jabvox_context_forge_handoffs_on_account_id", unique: true
  end

  create_table "jabvox_conversation_label_logs", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "conversation_id", null: false
    t.string "label_jabvox", null: false
    t.datetime "applied_at_jabvox", null: false
    t.datetime "removed_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "applied_at_jabvox", "id"], name: "idx_conv_label_logs_account_applied_keyset", order: { applied_at_jabvox: :desc, id: :desc }
    t.index ["account_id", "label_jabvox"], name: "idx_conv_label_logs_account_label"
    t.index ["account_id", "removed_at_jabvox", "id"], name: "idx_conv_label_logs_account_removed_keyset", order: { removed_at_jabvox: :desc, id: :desc }
    t.index ["conversation_id", "label_jabvox"], name: "idx_conv_label_logs_open_unique", unique: true, where: "(removed_at_jabvox IS NULL)"
    t.index ["conversation_id"], name: "idx_conv_label_logs_conversation"
  end

  create_table "jabvox_currencies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "symbol_jabvox", null: false
    t.string "name_jabvox", null: false
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "symbol_jabvox"], name: "index_jabvox_currencies_account_symbol", unique: true
    t.index ["account_id"], name: "index_jabvox_currencies_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_currencies_on_created_by_id"
  end

  create_table "jabvox_custom_columns", force: :cascade do |t|
    t.bigint "jabvox_custom_table_id", null: false
    t.string "name_jabvox", null: false
    t.string "label_jabvox", null: false
    t.string "column_type_jabvox", default: "text", null: false
    t.jsonb "options_jabvox", default: []
    t.boolean "required_jabvox", default: false, null: false
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "depends_on_jabvox"
    t.jsonb "show_when_jabvox", default: [], null: false
    t.index ["jabvox_custom_table_id", "name_jabvox"], name: "idx_jabvox_custom_columns_table_name", unique: true
    t.index ["jabvox_custom_table_id"], name: "index_jabvox_custom_columns_on_jabvox_custom_table_id"
  end

  create_table "jabvox_custom_table_rows", force: :cascade do |t|
    t.bigint "jabvox_custom_table_id", null: false
    t.bigint "contact_id"
    t.jsonb "data_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_jabvox_custom_table_rows_on_contact_id"
    t.index ["jabvox_custom_table_id"], name: "index_jabvox_custom_table_rows_on_jabvox_custom_table_id"
  end

  create_table "jabvox_custom_tables", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "linked_to_jabvox"
    t.string "kind_jabvox", default: "single", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "linked_to_jabvox"], name: "idx_jabvox_custom_tables_linked_to", unique: true, where: "(linked_to_jabvox IS NOT NULL)"
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_custom_tables_on_account_id_and_name_jabvox", unique: true
    t.index ["account_id"], name: "index_jabvox_custom_tables_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_custom_tables_on_created_by_id"
  end

  create_table "jabvox_dialer_accesses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.boolean "can_access", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "index_jabvox_dialer_accesses_account_user", unique: true
    t.index ["account_id"], name: "index_jabvox_dialer_accesses_on_account_id"
  end

  create_table "jabvox_dialer_call_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_dialer_campaign_id", null: false
    t.bigint "jabvox_dialer_campaign_contact_id", null: false
    t.bigint "agent_id_jabvox"
    t.string "phone_jabvox", default: "", null: false
    t.string "status_jabvox", default: "initiated", null: false
    t.integer "duration_jabvox", default: 0
    t.datetime "started_at_jabvox"
    t.datetime "ended_at_jabvox"
    t.text "notes_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "lead_answered_jabvox", default: false, null: false
    t.bigint "typification_id"
    t.string "uniqueid_jabvox"
    t.string "linkedid_jabvox"
    t.index ["account_id", "linkedid_jabvox"], name: "idx_dialer_logs_account_linkedid"
    t.index ["account_id", "started_at_jabvox"], name: "idx_dialer_logs_open_by_account", where: "((status_jabvox)::text = ANY (ARRAY[('initiated'::character varying)::text, ('calling'::character varying)::text]))"
    t.index ["account_id", "uniqueid_jabvox"], name: "idx_on_account_id_uniqueid_jabvox_8158b17c6d"
    t.index ["account_id"], name: "index_jabvox_dialer_call_logs_on_account_id"
    t.index ["agent_id_jabvox", "ended_at_jabvox"], name: "idx_dialer_logs_agent_open"
    t.index ["agent_id_jabvox"], name: "idx_dialer_logs_on_agent_id"
    t.index ["jabvox_dialer_campaign_contact_id"], name: "idx_dialer_logs_on_contact_id"
    t.index ["jabvox_dialer_campaign_id"], name: "idx_dialer_logs_on_campaign_id"
    t.index ["started_at_jabvox"], name: "index_jabvox_dialer_call_logs_on_started_at_jabvox"
    t.index ["typification_id"], name: "index_jabvox_dialer_call_logs_on_typification_id"
  end

  create_table "jabvox_dialer_campaign_contacts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_dialer_campaign_id", null: false
    t.string "name_jabvox", default: ""
    t.string "phone_jabvox", default: "", null: false
    t.string "status_jabvox", default: "pending", null: false
    t.integer "attempts_jabvox", default: 0, null: false
    t.datetime "last_attempt_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "contact_id"
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_dialer_campaign_contacts_on_account_id"
    t.index ["contact_id"], name: "index_jabvox_dialer_campaign_contacts_on_contact_id"
    t.index ["created_by_id"], name: "index_jabvox_dialer_campaign_contacts_on_created_by_id"
    t.index ["jabvox_dialer_campaign_id", "contact_id"], name: "idx_dialer_contacts_unique_campaign_contact", unique: true, where: "(contact_id IS NOT NULL)"
    t.index ["jabvox_dialer_campaign_id"], name: "idx_dialer_contacts_on_campaign_id"
    t.index ["status_jabvox"], name: "index_jabvox_dialer_campaign_contacts_on_status_jabvox"
  end

  create_table "jabvox_dialer_campaigns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", default: "", null: false
    t.text "description_jabvox"
    t.string "status_jabvox", default: "draft", null: false
    t.string "caller_id_jabvox", default: ""
    t.integer "max_concurrent_jabvox", default: 1, null: false
    t.integer "retry_count_jabvox", default: 0, null: false
    t.integer "retry_interval_jabvox", default: 60, null: false
    t.string "calling_hours_start_jabvox"
    t.string "calling_hours_end_jabvox"
    t.integer "total_contacts_jabvox", default: 0, null: false
    t.integer "dialed_count_jabvox", default: 0, null: false
    t.integer "answered_count_jabvox", default: 0, null: false
    t.integer "failed_count_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "jabvox_campaign_id"
    t.jsonb "countries_jabvox", default: []
    t.integer "wrapup_time_jabvox", default: 30
    t.integer "lines_per_agent_jabvox", default: 1
    t.jsonb "management_state_ids_jabvox", default: []
    t.jsonb "agent_ids_jabvox", default: []
    t.jsonb "affiliate_ids_jabvox", default: []
    t.jsonb "inbox_ids_jabvox", default: []
    t.integer "leads_count_jabvox", default: 0, null: false
    t.boolean "wait_in_queue_jabvox", default: true, null: false
    t.jsonb "lead_filters_jabvox", default: {}, null: false
    t.jsonb "excluded_lead_ids_jabvox", default: [], null: false
    t.date "schedule_start_date_jabvox"
    t.date "schedule_end_date_jabvox"
    t.string "dial_mode_jabvox", default: "last_state", null: false
    t.string "dial_field_jabvox"
    t.string "dial_prefix_jabvox"
    t.jsonb "retry_statuses_jabvox", default: [], null: false
    t.integer "max_retries_jabvox", default: 0, null: false
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_dialer_campaigns_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_dialer_campaigns_on_created_by_id"
    t.index ["jabvox_campaign_id"], name: "index_jabvox_dialer_campaigns_on_jabvox_campaign_id"
  end

  create_table "jabvox_dialer_state_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "dialer_state", default: "inactive", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id", "started_at"], name: "idx_on_account_id_user_id_started_at_ee4c1f49a2"
    t.index ["account_id"], name: "index_jabvox_dialer_state_logs_on_account_id"
    t.index ["user_id", "ended_at"], name: "index_jabvox_dialer_state_logs_on_user_id_and_ended_at"
  end

  create_table "jabvox_dialer_states", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "color", default: "#64748b"
    t.integer "position", default: 0
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_dialer_states_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_dialer_states_on_created_by_id"
  end

  create_table "jabvox_discounts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.decimal "percentage_jabvox", precision: 5, scale: 2, default: "0.0", null: false
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_discounts_account_name", unique: true
    t.index ["account_id"], name: "index_jabvox_discounts_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_discounts_on_created_by_id"
  end

  create_table "jabvox_email_send_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "to_email", null: false
    t.string "subject", default: "", null: false
    t.string "status", default: "sent", null: false
    t.string "source", default: "manual", null: false
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_jabvox_email_send_logs_on_account_id_and_created_at"
    t.index ["account_id", "status"], name: "index_jabvox_email_send_logs_on_account_id_and_status"
    t.index ["account_id"], name: "index_jabvox_email_send_logs_on_account_id"
    t.index ["user_id"], name: "index_jabvox_email_send_logs_on_user_id"
  end

  create_table "jabvox_email_templates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "subject"
    t.text "body"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "name"], name: "index_jabvox_email_templates_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_jabvox_email_templates_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_email_templates_on_created_by_id"
  end

  create_table "jabvox_export_sync_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_export_target_id", null: false
    t.string "model_name_jabvox", null: false
    t.bigint "record_id_jabvox", null: false
    t.string "status_jabvox", default: "queued", null: false
    t.string "operation_jabvox", default: "realtime", null: false
    t.string "error_jabvox"
    t.integer "attempts_jabvox", default: 0, null: false
    t.datetime "last_attempt_at_jabvox"
    t.datetime "exported_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status_jabvox"], name: "index_jabvox_export_sync_logs_on_account_id_and_status_jabvox"
    t.index ["account_id"], name: "index_jabvox_export_sync_logs_on_account_id"
    t.index ["jabvox_export_target_id", "model_name_jabvox", "record_id_jabvox"], name: "idx_export_sync_logs_unique_record", unique: true
    t.index ["jabvox_export_target_id", "status_jabvox", "last_attempt_at_jabvox"], name: "idx_export_sync_logs_target_status"
    t.index ["jabvox_export_target_id"], name: "index_jabvox_export_sync_logs_on_jabvox_export_target_id"
  end

  create_table "jabvox_export_targets", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "engine_jabvox", null: false
    t.string "host_jabvox"
    t.integer "port_jabvox"
    t.string "database_jabvox"
    t.string "username_jabvox"
    t.text "password_jabvox"
    t.string "ssl_mode_jabvox", default: "prefer", null: false
    t.boolean "allow_private_network_jabvox", default: false, null: false
    t.integer "query_timeout_ms_jabvox", default: 15000, null: false
    t.boolean "enabled_jabvox", default: false, null: false
    t.datetime "schema_built_at_jabvox"
    t.string "status_jabvox", default: "untested", null: false
    t.datetime "last_tested_at_jabvox"
    t.datetime "last_export_at_jabvox"
    t.string "last_error_jabvox"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mode_jabvox", default: "create", null: false
    t.jsonb "field_mapping_jabvox", default: {}, null: false
    t.boolean "create_missing_columns_jabvox", default: false, null: false
    t.datetime "last_full_sync_at_jabvox"
    t.jsonb "last_sync_result_jabvox", default: {}, null: false
    t.string "sync_status_jabvox", default: "idle", null: false
    t.jsonb "selected_modules_jabvox", default: [], null: false
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_export_targets_on_account_id_and_name_jabvox", unique: true
    t.index ["account_id"], name: "idx_export_targets_one_per_account", unique: true
    t.index ["account_id"], name: "index_jabvox_export_targets_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_export_targets_on_created_by_id"
  end

  create_table "jabvox_field_visibilities", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "field_name", null: false
    t.boolean "can_view", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id", "field_name"], name: "idx_jabvox_field_visibility_unique", unique: true
    t.index ["account_id"], name: "index_jabvox_field_visibilities_on_account_id"
    t.index ["user_id"], name: "index_jabvox_field_visibilities_on_user_id"
  end

  create_table "jabvox_flow_account_variables", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "key", null: false
    t.text "value", default: "", null: false
    t.boolean "secret", default: false, null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "key"], name: "idx_jabvox_flow_vars_account_key", unique: true
  end

  create_table "jabvox_flow_folders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "idx_jabvox_flow_folders_account_name", unique: true
  end

  create_table "jabvox_flow_run_steps", force: :cascade do |t|
    t.bigint "flow_run_id", null: false
    t.string "node_id", null: false
    t.string "node_type", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "input"
    t.jsonb "output"
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["flow_run_id", "id"], name: "idx_jabvox_flow_run_steps_run"
  end

  create_table "jabvox_flow_runs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "flow_id", null: false
    t.bigint "version_id", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "trigger", default: {}, null: false
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.string "waiting_node_id"
    t.string "wait_reason"
    t.datetime "resume_at"
    t.jsonb "wait_state"
    t.bigint "triggered_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "idx_jabvox_flow_runs_account_status"
    t.index ["flow_id", "created_at"], name: "idx_jabvox_flow_runs_flow_created"
    t.index ["status", "resume_at"], name: "idx_jabvox_flow_runs_status_resume"
  end

  create_table "jabvox_flow_versions", force: :cascade do |t|
    t.bigint "flow_id", null: false
    t.integer "version", null: false
    t.jsonb "graph", default: {}, null: false
    t.bigint "created_by"
    t.datetime "created_at", null: false
    t.index ["flow_id", "version"], name: "idx_jabvox_flow_versions_flow_version", unique: true
  end

  create_table "jabvox_flows", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.bigint "current_version_id"
    t.bigint "folder_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_token"
    t.index ["account_id", "folder_id"], name: "idx_jabvox_flows_account_folder"
    t.index ["account_id", "status"], name: "idx_jabvox_flows_account_status"
    t.index ["webhook_token"], name: "index_jabvox_flows_on_webhook_token", unique: true
  end

  create_table "jabvox_form_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "base_url_jabvox", default: ""
    t.integer "max_forms_jabvox", default: 10, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ssl_status", default: "none", null: false
    t.text "ssl_cert"
    t.text "ssl_key"
    t.datetime "ssl_expires_at"
    t.string "ssl_error", limit: 500
    t.datetime "ssl_provisioned_at"
    t.text "acme_account_key"
    t.index ["account_id"], name: "index_jabvox_form_configs_on_account_id", unique: true
  end

  create_table "jabvox_form_submissions", force: :cascade do |t|
    t.bigint "jabvox_form_id", null: false
    t.bigint "account_id", null: false
    t.jsonb "data_jabvox", default: {}
    t.string "ip_address_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_form_submissions_on_account_id"
    t.index ["created_at"], name: "index_jabvox_form_submissions_on_created_at"
    t.index ["created_by_id"], name: "index_jabvox_form_submissions_on_created_by_id"
    t.index ["jabvox_form_id"], name: "index_jabvox_form_submissions_on_jabvox_form_id"
  end

  create_table "jabvox_forms", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "slug_jabvox", null: false
    t.jsonb "header_jabvox", default: {}
    t.jsonb "footer_jabvox", default: {}
    t.jsonb "fields_jabvox", default: []
    t.jsonb "submit_actions_jabvox", default: {}
    t.string "submit_button_text_jabvox", default: "Enviar"
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_forms_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_forms_on_created_by_id"
    t.index ["slug_jabvox"], name: "index_jabvox_forms_on_slug_jabvox", unique: true
  end

  create_table "jabvox_hermes_action_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "hermes_identity_jabvox"
    t.string "tool_jabvox", null: false
    t.string "permission_jabvox"
    t.jsonb "params_jabvox", default: {}
    t.string "status_jabvox", null: false
    t.text "error_jabvox"
    t.integer "duration_ms_jabvox"
    t.datetime "created_at", null: false
    t.index ["account_id", "created_at"], name: "index_jabvox_hermes_action_logs_on_account_id_and_created_at"
    t.index ["account_id", "tool_jabvox"], name: "index_jabvox_hermes_action_logs_on_account_id_and_tool_jabvox"
    t.index ["account_id"], name: "index_jabvox_hermes_action_logs_on_account_id"
    t.index ["user_id"], name: "index_jabvox_hermes_action_logs_on_user_id"
  end

  create_table "jabvox_hermes_agent_connections", force: :cascade do |t|
    t.bigint "hermes_agent_id", null: false
    t.bigint "hermes_connection_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hermes_agent_id", "hermes_connection_id"], name: "idx_hermes_agent_conn_unique", unique: true
    t.index ["hermes_agent_id"], name: "index_jabvox_hermes_agent_connections_on_hermes_agent_id"
    t.index ["hermes_connection_id"], name: "idx_hermes_conn_single_agent", unique: true
    t.index ["hermes_connection_id"], name: "index_jabvox_hermes_agent_connections_on_hermes_connection_id"
  end

  create_table "jabvox_hermes_agents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.text "system_prompt_jabvox"
    t.boolean "is_default_jabvox", default: false, null: false
    t.string "status_jabvox", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "agent_token_jabvox"
    t.index ["account_id", "user_id"], name: "idx_hermes_agents_account_user", unique: true
    t.index ["account_id"], name: "index_jabvox_hermes_agents_on_account_id"
    t.index ["agent_token_jabvox"], name: "idx_hermes_agents_token", unique: true, where: "(agent_token_jabvox IS NOT NULL)"
    t.index ["user_id"], name: "index_jabvox_hermes_agents_on_user_id"
  end

  create_table "jabvox_hermes_connections", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "hermes_agent_name_jabvox", null: false
    t.string "base_url_jabvox", null: false
    t.text "token_jabvox"
    t.string "status_jabvox", default: "unknown", null: false
    t.string "last_error_jabvox"
    t.datetime "last_check_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "action_token_jabvox"
    t.string "allowed_ips_jabvox", default: [], null: false, array: true
    t.index ["account_id", "hermes_agent_name_jabvox"], name: "idx_hermes_conn_account_agent", unique: true
    t.index ["account_id"], name: "index_jabvox_hermes_connections_on_account_id"
    t.index ["action_token_jabvox"], name: "idx_hermes_conn_action_token", unique: true, where: "(action_token_jabvox IS NOT NULL)"
  end

  create_table "jabvox_hermes_identities", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "status_jabvox", default: "active", null: false
    t.datetime "last_seen_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_hermes_identities_on_account_id", unique: true
  end

  create_table "jabvox_hermes_provisioner_links", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "hermes_provisioner_id", null: false
    t.string "status_jabvox", default: "linked", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_hermes_provisioner_links_on_account_id", unique: true
    t.index ["hermes_provisioner_id"], name: "index_jabvox_hermes_provisioner_links_on_hermes_provisioner_id"
  end

  create_table "jabvox_hermes_provisioners", force: :cascade do |t|
    t.string "name_jabvox", default: "Hermes Aprovisionador", null: false
    t.string "base_url_jabvox"
    t.text "service_token_jabvox"
    t.string "status_jabvox", default: "disconnected", null: false
    t.datetime "last_check_at_jabvox"
    t.text "last_error_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "hermes_agent_name_jabvox"
  end

  create_table "jabvox_hermes_sessions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "kind_jabvox", default: "account", null: false
    t.string "session_id_jabvox"
    t.datetime "last_used_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id", "kind_jabvox"], name: "idx_hermes_sessions_account_user_kind", unique: true
    t.index ["account_id"], name: "index_jabvox_hermes_sessions_on_account_id"
    t.index ["user_id"], name: "index_jabvox_hermes_sessions_on_user_id"
  end

  create_table "jabvox_hermes_user_permissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.jsonb "permissions_jabvox", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "idx_hermes_user_perms_unique", unique: true
    t.index ["account_id"], name: "index_jabvox_hermes_user_permissions_on_account_id"
    t.index ["user_id"], name: "index_jabvox_hermes_user_permissions_on_user_id"
  end

  create_table "jabvox_integration_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "integration_type_jabvox", default: "alegra"
    t.text "integration_email_jabvox"
    t.text "integration_token_jabvox"
    t.string "company_name_jabvox"
    t.string "company_nit_jabvox"
    t.text "company_address_jabvox"
    t.string "company_phone_jabvox"
    t.string "company_email_jabvox"
    t.string "company_website_jabvox"
    t.text "company_logo_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_integration_configs_on_account_id", unique: true
  end

  create_table "jabvox_internal_chat_members", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.bigint "user_id", null: false
    t.integer "unread_count", default: 0, null: false
    t.datetime "last_read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "user_id"], name: "index_jabvox_internal_chat_members_on_chat_id_and_user_id", unique: true
    t.index ["chat_id"], name: "index_jabvox_internal_chat_members_on_chat_id"
    t.index ["user_id"], name: "index_jabvox_internal_chat_members_on_user_id"
  end

  create_table "jabvox_internal_chats", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name"
    t.integer "chat_type", default: 0, null: false
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_internal_chats_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_internal_chats_on_created_by_id"
  end

  create_table "jabvox_internal_messages", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.bigint "sender_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_jabvox_internal_messages_on_chat_id"
    t.index ["sender_id"], name: "index_jabvox_internal_messages_on_sender_id"
  end

  create_table "jabvox_ip_whitelists", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "ip", limit: 45, null: false
    t.boolean "is_active", default: true, null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "ip"], name: "index_jabvox_ip_whitelists_on_account_id_and_ip", unique: true
    t.index ["account_id"], name: "index_jabvox_ip_whitelists_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_ip_whitelists_on_created_by_id"
  end

  create_table "jabvox_item_types", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_item_types_account_name", unique: true
    t.index ["account_id"], name: "index_jabvox_item_types_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_item_types_on_created_by_id"
  end

  create_table "jabvox_kanban_conversation_stages", force: :cascade do |t|
    t.bigint "conversation_id"
    t.bigint "jabvox_kanban_funnel_id", null: false
    t.bigint "jabvox_kanban_stage_id", null: false
    t.bigint "account_id", null: false
    t.bigint "moved_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.bigint "contact_id"
    t.integer "position_jabvox", default: 0, null: false
    t.index ["account_id", "contact_id"], name: "idx_on_account_id_contact_id_15c04b9163"
    t.index ["account_id"], name: "index_jabvox_conv_stages_account"
    t.index ["conversation_id", "jabvox_kanban_funnel_id"], name: "index_jabvox_conv_stages_unique", unique: true
    t.index ["created_by_id"], name: "index_jabvox_kanban_conversation_stages_on_created_by_id"
    t.index ["jabvox_kanban_funnel_id"], name: "index_jabvox_conv_stages_funnel"
    t.index ["jabvox_kanban_stage_id", "position_jabvox"], name: "idx_jabvox_conv_stages_stage_position"
    t.index ["jabvox_kanban_stage_id"], name: "index_jabvox_conv_stages_stage"
  end

  create_table "jabvox_kanban_funnel_affiliates", force: :cascade do |t|
    t.bigint "jabvox_kanban_funnel_id", null: false
    t.bigint "jabvox_affiliate_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jabvox_kanban_funnel_id", "jabvox_affiliate_id"], name: "idx_kanban_funnel_affiliates_unique", unique: true
  end

  create_table "jabvox_kanban_funnel_campaigns", force: :cascade do |t|
    t.bigint "jabvox_kanban_funnel_id", null: false
    t.bigint "jabvox_campaign_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jabvox_kanban_funnel_id", "jabvox_campaign_id"], name: "idx_kanban_funnel_campaigns_unique", unique: true
  end

  create_table "jabvox_kanban_funnel_inboxes", force: :cascade do |t|
    t.bigint "jabvox_kanban_funnel_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inbox_id"], name: "index_jabvox_kanban_funnel_inboxes_on_inbox_id"
    t.index ["jabvox_kanban_funnel_id", "inbox_id"], name: "index_jabvox_funnel_inboxes_unique", unique: true
    t.index ["jabvox_kanban_funnel_id"], name: "index_jabvox_kanban_funnel_inboxes_on_jabvox_kanban_funnel_id"
  end

  create_table "jabvox_kanban_funnels", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.integer "position_jabvox", default: 0, null: false
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "include_own_contacts_jabvox", default: false, null: false
    t.bigint "created_by_id"
    t.string "lifecycle_stages_jabvox", default: [], null: false, array: true
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_kanban_funnels_on_account_id_and_name_jabvox", unique: true
    t.index ["account_id"], name: "index_jabvox_kanban_funnels_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_kanban_funnels_on_created_by_id"
    t.index ["lifecycle_stages_jabvox"], name: "index_jabvox_kanban_funnels_on_lifecycle_stages_jabvox", using: :gin
  end

  create_table "jabvox_kanban_stage_automations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_kanban_stage_id", null: false
    t.string "name", null: false
    t.string "channel_type"
    t.bigint "inbox_id"
    t.bigint "jabvox_email_template_id"
    t.bigint "jabvox_sms_provider_id"
    t.text "message_body"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "automation_type", default: "send_message", null: false
    t.integer "trigger_hours"
    t.bigint "target_stage_id"
    t.bigint "created_by_id"
    t.string "trigger_unit_jabvox"
    t.integer "trigger_value_jabvox"
    t.string "template_name_jabvox"
    t.string "template_language_jabvox"
    t.jsonb "template_params_jabvox", default: {}, null: false
    t.index ["account_id"], name: "index_jabvox_kanban_stage_automations_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_kanban_stage_automations_on_created_by_id"
    t.index ["inbox_id"], name: "index_jabvox_kanban_stage_automations_on_inbox_id"
    t.index ["jabvox_kanban_stage_id"], name: "index_jabvox_kanban_stage_automations_on_jabvox_kanban_stage_id"
    t.index ["target_stage_id"], name: "index_jabvox_stage_automations_on_target_stage"
  end

  create_table "jabvox_kanban_stages", force: :cascade do |t|
    t.bigint "jabvox_kanban_funnel_id", null: false
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.integer "position_jabvox", default: 0, null: false
    t.string "color_jabvox", default: "#6B7280", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "auto_advance_enabled", default: false, null: false
    t.integer "auto_advance_hours"
    t.bigint "auto_advance_target_stage_id"
    t.bigint "created_by_id"
    t.string "card_sort_jabvox", default: "manual", null: false
    t.index ["account_id"], name: "index_jabvox_kanban_stages_on_account_id"
    t.index ["auto_advance_target_stage_id"], name: "index_jabvox_kanban_stages_on_auto_advance_target"
    t.index ["created_by_id"], name: "index_jabvox_kanban_stages_on_created_by_id"
    t.index ["jabvox_kanban_funnel_id", "position_jabvox"], name: "index_jabvox_stages_funnel_position"
    t.index ["jabvox_kanban_funnel_id"], name: "index_jabvox_kanban_stages_on_jabvox_kanban_funnel_id"
  end

  create_table "jabvox_lead_source_records", force: :cascade do |t|
    t.bigint "lead_source_id", null: false
    t.bigint "account_id", null: false
    t.string "external_id_jabvox", null: false
    t.datetime "last_synced_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "contact_id", null: false
    t.index ["account_id", "contact_id"], name: "index_jabvox_lead_source_records_on_account_id_and_contact_id"
    t.index ["account_id"], name: "index_jabvox_lead_source_records_on_account_id"
    t.index ["lead_source_id", "external_id_jabvox"], name: "index_jabvox_lead_source_records_on_source_and_external_id", unique: true
    t.index ["lead_source_id"], name: "index_jabvox_lead_source_records_on_lead_source_id"
  end

  create_table "jabvox_lead_sources", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "engine_jabvox", null: false
    t.string "host_jabvox"
    t.integer "port_jabvox"
    t.string "database_jabvox"
    t.string "username_jabvox"
    t.text "password_jabvox"
    t.string "ssl_mode_jabvox", default: "prefer", null: false
    t.boolean "allow_private_network_jabvox", default: false, null: false
    t.integer "query_timeout_ms_jabvox", default: 30000, null: false
    t.string "table_jabvox"
    t.string "external_id_column_jabvox"
    t.jsonb "field_mapping_jabvox", default: {}, null: false
    t.string "status_jabvox", default: "untested", null: false
    t.datetime "last_tested_at_jabvox"
    t.datetime "last_synced_at_jabvox"
    t.jsonb "last_sync_result_jabvox", default: {}, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "related_tables_jabvox", default: [], null: false
    t.jsonb "filters_jabvox", default: [], null: false
    t.string "phone_prefix_jabvox", default: "", null: false
    t.string "country_jabvox", default: "", null: false
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_lead_sources_on_account_id_and_name_jabvox", unique: true
    t.index ["account_id"], name: "index_jabvox_lead_sources_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_lead_sources_on_created_by_id"
  end

  create_table "jabvox_management_answers", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_management_state_id"
    t.bigint "jabvox_management_question_id"
    t.bigint "message_id"
    t.bigint "note_id"
    t.string "label", default: "", null: false
    t.string "value_type", default: "text", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "created_at", "id"], name: "idx_jabvox_mgmt_answers_account_created_keyset", order: { created_at: :desc, id: :desc }
    t.index ["account_id"], name: "index_jabvox_management_answers_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_management_answers_on_created_by_id"
    t.index ["jabvox_management_question_id"], name: "idx_on_jabvox_management_question_id_65239e4ba3"
    t.index ["jabvox_management_state_id"], name: "index_jabvox_management_answers_on_jabvox_management_state_id"
    t.index ["message_id"], name: "index_jabvox_management_answers_on_message_id"
    t.index ["note_id"], name: "index_jabvox_management_answers_on_note_id"
  end

  create_table "jabvox_management_questions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_management_state_id", null: false
    t.string "label", null: false
    t.string "question_type", default: "text", null: false
    t.jsonb "options", default: [], null: false
    t.boolean "required", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "visibility", default: {}, null: false
    t.string "lead_field", default: "", null: false
    t.boolean "lead_field_locked", default: false, null: false
    t.string "question_key"
    t.bigint "created_by_id"
    t.index ["account_id", "question_key"], name: "idx_mgmt_questions_account_question_key"
    t.index ["account_id"], name: "index_jabvox_management_questions_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_management_questions_on_created_by_id"
    t.index ["jabvox_management_state_id", "position"], name: "idx_on_jabvox_management_state_id_position_5047167b84"
    t.index ["jabvox_management_state_id"], name: "idx_on_jabvox_management_state_id_5c2de1c51d"
  end

  create_table "jabvox_management_states", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", default: "", null: false
    t.string "color_jabvox", default: "#6366f1", null: false
    t.boolean "is_active_jabvox", default: true, null: false
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "note_mode", default: "optional", null: false
    t.string "state_group_jabvox", default: "", null: false
    t.text "usage_info_jabvox", default: "", null: false
    t.boolean "managed_jabvox", default: true, null: false
    t.boolean "contact_jabvox", default: false, null: false
    t.boolean "effective_contact_jabvox", default: false, null: false
    t.boolean "advisory_jabvox", default: false, null: false
    t.string "service_type_jabvox", default: "No", null: false
    t.integer "positivity_level_jabvox", default: 0, null: false
    t.bigint "created_by_id"
    t.index ["account_id", "state_group_jabvox"], name: "idx_jabvox_mgmt_states_on_account_and_group"
    t.index ["account_id"], name: "index_jabvox_management_states_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_management_states_on_created_by_id"
  end

  create_table "jabvox_order_items", force: :cascade do |t|
    t.bigint "jabvox_order_id", null: false
    t.bigint "jabvox_product_id"
    t.string "name_snapshot", null: false
    t.decimal "unit_price", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "quantity", precision: 10, scale: 2, default: "1.0", null: false
    t.decimal "discount_pct", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "tax_pct", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "line_total", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jabvox_order_id"], name: "index_jabvox_order_items_on_jabvox_order_id"
    t.index ["jabvox_product_id"], name: "index_jabvox_order_items_on_jabvox_product_id"
  end

  create_table "jabvox_order_status_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "key_jabvox", null: false
    t.string "label_jabvox", null: false
    t.integer "sort_order_jabvox", default: 0, null: false
    t.string "color_jabvox", default: "#6B7280", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "key_jabvox"], name: "index_jabvox_order_status_account_key", unique: true
    t.index ["account_id"], name: "index_jabvox_order_status_configs_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_order_status_configs_on_created_by_id"
  end

  create_table "jabvox_orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "contact_id"
    t.bigint "conversation_id"
    t.string "doc_type", default: "QUOTE", null: false
    t.string "status", default: "draft", null: false
    t.text "notes"
    t.decimal "subtotal", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "tax_total", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "discount_total", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "total", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "alegra_id"
    t.string "alegra_number"
    t.bigint "created_by_id"
    t.index ["account_id", "created_at", "id"], name: "idx_jabvox_orders_account_created_keyset", order: { created_at: :desc, id: :desc }
    t.index ["account_id"], name: "index_jabvox_orders_on_account_id"
    t.index ["contact_id"], name: "index_jabvox_orders_on_contact_id"
    t.index ["conversation_id"], name: "index_jabvox_orders_on_conversation_id"
    t.index ["created_by_id"], name: "index_jabvox_orders_on_created_by_id"
  end

  create_table "jabvox_payment_gateway_configs", force: :cascade do |t|
    t.string "provider", null: false
    t.boolean "active", default: false, null: false
    t.string "public_token"
    t.string "checkout_base_url"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "api_key"
    t.text "secret_key"
    t.boolean "sandbox", default: false, null: false
    t.index ["active"], name: "idx_one_active_gateway", unique: true, where: "(active = true)"
    t.index ["provider"], name: "index_jabvox_payment_gateway_configs_on_provider", unique: true
  end

  create_table "jabvox_plans", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "price_cents", default: 0, null: false
    t.string "currency", default: "COP", null: false
    t.integer "duration_days", default: 30, null: false
    t.jsonb "modules", default: [], null: false
    t.jsonb "chatwoot_features", default: [], null: false
    t.jsonb "limits", default: {}, null: false
    t.string "whatsapp_number"
    t.integer "status", default: 0, null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "billing_period", default: 0, null: false
    t.integer "ai_budget_cents_jabvox", default: 0, null: false
    t.index ["slug"], name: "index_jabvox_plans_on_slug", unique: true
    t.index ["status"], name: "index_jabvox_plans_on_status"
  end

  create_table "jabvox_products", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.decimal "price_jabvox", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "base_price_jabvox", precision: 12, scale: 2
    t.decimal "tax_percentage_jabvox", precision: 5, scale: 2
    t.decimal "total_price_jabvox", precision: 12, scale: 2
    t.boolean "active_jabvox", default: true, null: false
    t.string "product_type_jabvox", default: "product", null: false
    t.integer "integration_item_id_jabvox"
    t.bigint "jabvox_currency_id"
    t.bigint "jabvox_item_type_id"
    t.bigint "jabvox_unit_of_measure_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_products_account_name", unique: true
    t.index ["account_id"], name: "index_jabvox_products_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_products_on_created_by_id"
    t.index ["jabvox_currency_id"], name: "index_jabvox_products_on_jabvox_currency_id"
    t.index ["jabvox_item_type_id"], name: "index_jabvox_products_on_jabvox_item_type_id"
    t.index ["jabvox_unit_of_measure_id"], name: "index_jabvox_products_on_jabvox_unit_of_measure_id"
  end

  create_table "jabvox_provisioner_api_tokens", force: :cascade do |t|
    t.string "token_hash_jabvox", null: false
    t.text "signing_secret_jabvox"
    t.string "token_prefix_jabvox", null: false
    t.string "status_jabvox", default: "active", null: false
    t.jsonb "allowed_ips_jabvox", default: [], null: false
    t.jsonb "permissions_jabvox", default: {}, null: false
    t.string "label_jabvox"
    t.bigint "created_by_id"
    t.datetime "last_used_at_jabvox"
    t.datetime "revoked_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status_jabvox"], name: "idx_one_active_provisioner_token", unique: true, where: "((status_jabvox)::text = 'active'::text)"
    t.index ["token_hash_jabvox"], name: "idx_provisioner_token_hash", unique: true
  end

  create_table "jabvox_provisioner_audit_logs", force: :cascade do |t|
    t.bigint "provisioner_api_token_id"
    t.string "resource_jabvox"
    t.string "action_jabvox"
    t.string "outcome_jabvox", null: false
    t.string "reason_jabvox"
    t.string "ip_jabvox"
    t.integer "account_context_id"
    t.jsonb "params_jabvox", default: {}, null: false
    t.integer "http_status_jabvox"
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "idx_provisioner_audit_created"
    t.index ["resource_jabvox", "action_jabvox"], name: "idx_provisioner_audit_resource"
  end

  create_table "jabvox_provisioner_nonces", force: :cascade do |t|
    t.string "nonce_jabvox", null: false
    t.datetime "seen_at_jabvox", null: false
    t.index ["nonce_jabvox"], name: "idx_provisioner_nonce", unique: true
    t.index ["seen_at_jabvox"], name: "idx_provisioner_nonce_seen"
  end

  create_table "jabvox_provisioner_sessions", force: :cascade do |t|
    t.bigint "provisioner_api_token_id", null: false
    t.string "client_id_jabvox", null: false
    t.string "bound_ip_jabvox", null: false
    t.string "fingerprint_jabvox"
    t.string "status_jabvox", default: "active", null: false
    t.datetime "last_heartbeat_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provisioner_api_token_id"], name: "index_jabvox_provisioner_sessions_on_provisioner_api_token_id"
    t.index ["status_jabvox"], name: "idx_one_active_provisioner_session", unique: true, where: "((status_jabvox)::text = 'active'::text)"
  end

  create_table "jabvox_provisioning_chat_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "role", null: false
    t.text "content"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "session_id", null: false
    t.string "status_jabvox"
    t.index ["account_id", "created_at"], name: "idx_on_account_id_created_at_0050c7615e"
    t.index ["account_id", "session_id", "created_at"], name: "idx_jabvox_prov_chat_on_account_session_created"
    t.index ["account_id"], name: "index_jabvox_provisioning_chat_messages_on_account_id"
    t.index ["session_id", "status_jabvox"], name: "idx_jabvox_prov_chat_on_session_status"
    t.index ["user_id"], name: "index_jabvox_provisioning_chat_messages_on_user_id"
  end

  create_table "jabvox_provisioning_transactions", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "jabvox_plan_id"
    t.string "buyer_email"
    t.string "gateway", null: false
    t.string "gateway_reference"
    t.string "idempotency_key", null: false
    t.integer "amount_cents"
    t.string "currency", default: "COP"
    t.integer "status", default: 0, null: false
    t.string "status_reason"
    t.integer "attempts", default: 0, null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "payment_approved_at"
    t.datetime "provisioned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_provisioning_transactions_on_account_id"
    t.index ["gateway_reference"], name: "index_jabvox_provisioning_transactions_on_gateway_reference"
    t.index ["idempotency_key"], name: "index_jabvox_provisioning_transactions_on_idempotency_key", unique: true
    t.index ["jabvox_plan_id"], name: "index_jabvox_provisioning_transactions_on_jabvox_plan_id"
    t.index ["status"], name: "index_jabvox_provisioning_transactions_on_status"
  end

  create_table "jabvox_quick_buttons", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "url_jabvox", null: false
    t.string "color_jabvox", default: "#6b7280"
    t.boolean "active_jabvox", default: true, null: false
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_quick_buttons_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_quick_buttons_on_created_by_id"
  end

  create_table "jabvox_report_daily_rollups", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "metric_key", null: false
    t.date "day", null: false
    t.bigint "inbox_id"
    t.bigint "user_id"
    t.bigint "count", default: 0, null: false
    t.decimal "sum_value", precision: 18, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "metric_key", "day", "inbox_id", "user_id"], name: "idx_jabvox_report_rollups_bucket", unique: true
    t.index ["account_id", "metric_key", "day"], name: "idx_jabvox_report_rollups_read"
  end

  create_table "jabvox_response_bot_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_response_bot_seat_id"
    t.bigint "inbox_id", null: false
    t.boolean "enabled_jabvox", default: false, null: false
    t.jsonb "active_labels_jabvox", default: ["proceso_venta", "proceso_pago", "quejas_y_reclamos", "soporte"]
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "jabvox_ai_chat_model_id"
    t.bigint "jabvox_audio_model_id"
    t.bigint "jabvox_response_bot_role_id"
    t.string "name_jabvox"
    t.text "description_jabvox"
    t.bigint "jabvox_image_model_id"
    t.string "google_maps_api_key_jabvox"
    t.string "company_address_jabvox"
    t.decimal "price_per_km_jabvox", precision: 10, scale: 2
    t.index ["account_id", "inbox_id"], name: "idx_response_bot_configs_account_inbox", unique: true
    t.index ["inbox_id"], name: "index_jabvox_response_bot_configs_on_inbox_id"
    t.index ["jabvox_ai_chat_model_id"], name: "index_jabvox_response_bot_configs_on_jabvox_ai_chat_model_id"
    t.index ["jabvox_audio_model_id"], name: "idx_response_bot_configs_audio_model"
    t.index ["jabvox_image_model_id"], name: "idx_response_bot_configs_image_model"
    t.index ["jabvox_response_bot_role_id"], name: "idx_response_bot_configs_role"
    t.index ["jabvox_response_bot_seat_id"], name: "idx_on_jabvox_response_bot_seat_id_b150b81444"
  end

  create_table "jabvox_response_bot_documents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "label_category_jabvox"
    t.string "name_jabvox", null: false
    t.string "s3_key_jabvox", null: false
    t.bigint "size_jabvox"
    t.string "content_type_jabvox"
    t.boolean "enabled_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "label_category_jabvox"], name: "idx_on_account_id_label_category_jabvox_d9404a8152"
    t.index ["account_id", "s3_key_jabvox"], name: "idx_on_account_id_s3_key_jabvox_1dc58f075a", unique: true
    t.index ["account_id"], name: "index_jabvox_response_bot_documents_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_response_bot_documents_on_created_by_id"
  end

  create_table "jabvox_response_bot_roles", force: :cascade do |t|
    t.string "name_jabvox", null: false
    t.text "prompt_jabvox"
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name_jabvox"], name: "index_jabvox_response_bot_roles_on_name_jabvox", unique: true
  end

  create_table "jabvox_response_bot_seats", force: :cascade do |t|
    t.string "name_jabvox", null: false
    t.text "prompt_jabvox"
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "jabvox_saldo_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", default: "", null: false
    t.string "base_url_jabvox", default: "", null: false
    t.text "api_key_jabvox"
    t.text "api_secret_jabvox"
    t.string "saldo_username_jabvox", default: "", null: false
    t.string "proxy_url_jabvox"
    t.boolean "use_proxy_jabvox", default: false, null: false
    t.boolean "is_active_jabvox", default: true, null: false
    t.decimal "cached_balance_jabvox", precision: 15, scale: 2
    t.datetime "balance_updated_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_saldo_configs_on_account_id", unique: true
  end

  create_table "jabvox_sales_report_accesses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.boolean "can_view_reports_jabvox", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "index_jabvox_report_access_account_user", unique: true
    t.index ["account_id"], name: "index_jabvox_sales_report_accesses_on_account_id"
  end

  create_table "jabvox_sms_campaigns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_sms_provider_id"
    t.string "name", null: false
    t.text "description"
    t.text "message", null: false
    t.string "status", default: "draft", null: false
    t.integer "sent_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.jsonb "contact_ids", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "jabvox_campaign_id"
    t.jsonb "inbox_ids_sms", default: []
    t.jsonb "affiliate_ids_sms", default: []
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_sms_campaigns_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_sms_campaigns_on_created_by_id"
    t.index ["jabvox_sms_provider_id"], name: "index_jabvox_sms_campaigns_on_jabvox_sms_provider_id"
  end

  create_table "jabvox_sms_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_sms_campaign_id"
    t.bigint "jabvox_sms_provider_id"
    t.bigint "contact_id"
    t.string "phone", null: false
    t.text "message", null: false
    t.string "status", default: "pending", null: false
    t.string "external_id"
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id"], name: "index_jabvox_sms_messages_on_account_id"
    t.index ["contact_id"], name: "index_jabvox_sms_messages_on_contact_id"
    t.index ["created_by_id"], name: "index_jabvox_sms_messages_on_created_by_id"
    t.index ["jabvox_sms_campaign_id"], name: "index_jabvox_sms_messages_on_jabvox_sms_campaign_id"
    t.index ["jabvox_sms_provider_id"], name: "index_jabvox_sms_messages_on_jabvox_sms_provider_id"
    t.index ["status"], name: "index_jabvox_sms_messages_on_status"
  end

  create_table "jabvox_sms_providers", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "base_url", null: false
    t.string "api_user", null: false
    t.text "api_password"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_sms_providers_on_account_id"
  end

  create_table "jabvox_smtp_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "from_name"
    t.string "from_email"
    t.string "address"
    t.integer "port", default: 587
    t.string "domain"
    t.string "username"
    t.text "password"
    t.string "authentication", default: "login"
    t.boolean "enable_starttls_auto", default: true
    t.boolean "enable_ssl_tls", default: false
    t.boolean "verified", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "calendar_reminders_enabled", default: false, null: false
    t.text "calendar_reminder_minutes"
    t.index ["account_id"], name: "index_jabvox_smtp_configs_on_account_id", unique: true
  end

  create_table "jabvox_softphone_call_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_softphone_call_log_id", null: false
    t.string "event_type", null: false
    t.string "detail"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "occurred_at"], name: "idx_on_account_id_occurred_at_0799b713a5"
    t.index ["account_id"], name: "index_jabvox_softphone_call_events_on_account_id"
    t.index ["jabvox_softphone_call_log_id"], name: "idx_sp_events_on_call_log"
  end

  create_table "jabvox_softphone_call_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "extension", null: false
    t.string "phone_number", null: false
    t.string "contact_name"
    t.integer "direction", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "started_at"
    t.datetime "answered_at"
    t.datetime "ended_at"
    t.integer "duration_seconds", default: 0, null: false
    t.string "call_uuid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "codec"
    t.string "failure_reason"
    t.string "failure_code"
    t.string "sip_context"
    t.string "remote_ip"
    t.string "ended_by"
    t.index ["account_id", "user_id", "created_at"], name: "idx_on_account_id_user_id_created_at_b9ba2ecdbd"
    t.index ["account_id"], name: "index_jabvox_softphone_call_logs_on_account_id"
    t.index ["call_uuid"], name: "index_jabvox_softphone_call_logs_on_call_uuid"
    t.index ["user_id"], name: "index_jabvox_softphone_call_logs_on_user_id"
  end

  create_table "jabvox_softphone_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "enabled", default: false, null: false
    t.string "wss_url"
    t.string "sip_domain"
    t.jsonb "codecs", default: ["opus", "alaw", "ulaw"], null: false
    t.boolean "auto_answer", default: false, null: false
    t.string "dtmf_mode", default: "rfc2833", null: false
    t.boolean "transfer_enabled", default: true, null: false
    t.string "default_context", default: "from-webrtc", null: false
    t.jsonb "stun_servers", default: [], null: false
    t.string "turn_url"
    t.text "turn_secret"
    t.integer "credential_ttl", default: 3600, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_softphone_configs_on_account_id", unique: true
  end

  create_table "jabvox_softphone_extensions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.text "sip_secret"
    t.boolean "webrtc_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "live_state", default: "disconnected", null: false
    t.datetime "last_seen_at"
    t.string "last_error"
    t.string "remote_ip"
    t.string "user_agent_info"
    t.index ["account_id", "user_id"], name: "index_jabvox_softphone_extensions_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_jabvox_softphone_extensions_on_account_id"
    t.index ["last_seen_at"], name: "index_jabvox_softphone_extensions_on_last_seen_at"
    t.index ["user_id"], name: "index_jabvox_softphone_extensions_on_user_id"
  end

  create_table "jabvox_task_activities", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "action_jabvox", null: false
    t.jsonb "metadata_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["account_id", "task_id", "created_at"], name: "index_jabvox_task_activities_on_account_task_created"
    t.index ["account_id"], name: "index_jabvox_task_activities_on_account_id"
    t.index ["task_id"], name: "index_jabvox_task_activities_on_task_id"
    t.index ["user_id"], name: "index_jabvox_task_activities_on_user_id"
  end

  create_table "jabvox_task_assignee_board_targets", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "source_board_id", null: false
    t.bigint "owner_id", null: false
    t.bigint "target_board_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_task_assignee_board_targets_on_account_id"
    t.index ["owner_id"], name: "index_jabvox_task_assignee_board_targets_on_owner_id"
    t.index ["source_board_id", "owner_id"], name: "index_jabvox_task_targets_on_source_and_owner", unique: true
    t.index ["source_board_id"], name: "index_jabvox_task_assignee_board_targets_on_source_board_id"
    t.index ["target_board_id"], name: "index_jabvox_task_assignee_board_targets_on_target_board_id"
  end

  create_table "jabvox_task_assignees", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_task_assignees_on_account_id"
    t.index ["task_id", "user_id"], name: "index_jabvox_task_assignees_on_task_and_user", unique: true
    t.index ["task_id"], name: "index_jabvox_task_assignees_on_task_id"
    t.index ["user_id"], name: "index_jabvox_task_assignees_on_user_id"
  end

  create_table "jabvox_task_automation_runs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "task_id", null: false
    t.bigint "automation_id"
    t.string "channel_jabvox", null: false
    t.string "status_jabvox", default: "sent", null: false
    t.integer "recipients_count_jabvox", default: 0, null: false
    t.text "detail_jabvox"
    t.datetime "run_at_jabvox", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "task_id", "run_at_jabvox"], name: "idx_on_account_id_task_id_run_at_jabvox_83a99062cf"
    t.index ["account_id"], name: "index_jabvox_task_automation_runs_on_account_id"
    t.index ["automation_id"], name: "index_jabvox_task_automation_runs_on_automation_id"
    t.index ["created_by_id"], name: "index_jabvox_task_automation_runs_on_created_by_id"
    t.index ["task_id"], name: "index_jabvox_task_automation_runs_on_task_id"
  end

  create_table "jabvox_task_automations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "task_id", null: false
    t.string "name_jabvox", default: "", null: false
    t.string "channel_jabvox", null: false
    t.string "recipients_jabvox", default: "lead", null: false
    t.string "manual_email_jabvox", default: "", null: false
    t.string "manual_phone_jabvox", default: "", null: false
    t.string "interval_unit_jabvox", default: "day", null: false
    t.integer "interval_count_jabvox", default: 1, null: false
    t.bigint "email_template_id"
    t.bigint "inbox_id"
    t.bigint "sms_provider_id"
    t.string "subject_jabvox", default: "", null: false
    t.text "body_jabvox"
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "start_at_jabvox"
    t.datetime "end_at_jabvox"
    t.datetime "next_run_at_jabvox"
    t.datetime "last_run_at_jabvox"
    t.integer "runs_count_jabvox", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "template_name_jabvox"
    t.string "template_language_jabvox"
    t.jsonb "template_params_jabvox", default: {}, null: false
    t.integer "max_runs_jabvox"
    t.string "schedule_mode_jabvox", default: "recurring", null: false
    t.jsonb "assignee_contact_map_jabvox", default: {}, null: false
    t.index ["account_id", "task_id"], name: "index_jabvox_task_automations_on_account_id_and_task_id"
    t.index ["account_id"], name: "index_jabvox_task_automations_on_account_id"
    t.index ["active_jabvox", "next_run_at_jabvox"], name: "idx_on_active_jabvox_next_run_at_jabvox_c67e09e205"
    t.index ["created_by_id"], name: "index_jabvox_task_automations_on_created_by_id"
    t.index ["email_template_id"], name: "index_jabvox_task_automations_on_email_template_id"
    t.index ["inbox_id"], name: "index_jabvox_task_automations_on_inbox_id"
    t.index ["sms_provider_id"], name: "index_jabvox_task_automations_on_sms_provider_id"
    t.index ["task_id"], name: "index_jabvox_task_automations_on_task_id"
  end

  create_table "jabvox_task_boards", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.integer "position_jabvox", default: 0, null: false
    t.boolean "is_active_jabvox", default: true, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "copy_to_assignee_board_jabvox", default: false, null: false
    t.bigint "owner_id"
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_task_boards_on_account_id_and_name_jabvox", unique: true
    t.index ["account_id"], name: "index_jabvox_task_boards_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_task_boards_on_created_by_id"
    t.index ["owner_id"], name: "index_jabvox_task_boards_on_owner_id"
  end

  create_table "jabvox_task_stage_automations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "stage_id", null: false
    t.string "automation_type_jabvox", null: false
    t.string "channel_type_jabvox"
    t.text "message_body_jabvox"
    t.bigint "inbox_id"
    t.bigint "email_template_id"
    t.bigint "sms_provider_id"
    t.string "webhook_url_jabvox"
    t.text "webhook_secret_jabvox"
    t.integer "trigger_hours_jabvox"
    t.bigint "target_stage_id"
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "template_name_jabvox"
    t.string "template_language_jabvox"
    t.jsonb "template_params_jabvox", default: {}, null: false
    t.string "trigger_unit_jabvox"
    t.integer "trigger_value_jabvox"
    t.index ["account_id", "stage_id"], name: "index_jabvox_task_stage_automations_on_account_id_and_stage_id"
    t.index ["account_id"], name: "index_jabvox_task_stage_automations_on_account_id"
    t.index ["email_template_id"], name: "index_jabvox_task_stage_automations_on_email_template_id"
    t.index ["inbox_id"], name: "index_jabvox_task_stage_automations_on_inbox_id"
    t.index ["sms_provider_id"], name: "index_jabvox_task_stage_automations_on_sms_provider_id"
    t.index ["stage_id"], name: "index_jabvox_task_stage_automations_on_stage_id"
    t.index ["target_stage_id"], name: "index_jabvox_task_stage_automations_on_target_stage_id"
  end

  create_table "jabvox_task_stages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "board_id", null: false
    t.string "name_jabvox", null: false
    t.string "color_jabvox", default: "#6b7280", null: false
    t.integer "position_jabvox", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.string "role_jabvox"
    t.string "card_sort_jabvox", default: "manual", null: false
    t.index ["account_id"], name: "index_jabvox_task_stages_on_account_id"
    t.index ["board_id", "position_jabvox"], name: "index_jabvox_task_stages_on_board_id_and_position_jabvox"
    t.index ["board_id", "role_jabvox"], name: "index_jabvox_task_stages_on_board_and_role", unique: true, where: "(role_jabvox IS NOT NULL)"
    t.index ["board_id"], name: "index_jabvox_task_stages_on_board_id"
    t.index ["created_by_id"], name: "index_jabvox_task_stages_on_created_by_id"
  end

  create_table "jabvox_task_webhook_deliveries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "task_id"
    t.bigint "automation_id"
    t.string "url_jabvox", null: false
    t.string "status_jabvox", default: "pending", null: false
    t.integer "response_code_jabvox"
    t.text "error_jabvox"
    t.jsonb "payload_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "created_at"], name: "idx_on_account_id_created_at_5aabb85ef6"
    t.index ["account_id"], name: "index_jabvox_task_webhook_deliveries_on_account_id"
    t.index ["automation_id"], name: "index_jabvox_task_webhook_deliveries_on_automation_id"
    t.index ["created_by_id"], name: "index_jabvox_task_webhook_deliveries_on_created_by_id"
    t.index ["task_id"], name: "index_jabvox_task_webhook_deliveries_on_task_id"
  end

  create_table "jabvox_tasks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "board_id", null: false
    t.bigint "stage_id", null: false
    t.bigint "assignee_id"
    t.string "title_jabvox", null: false
    t.text "description_jabvox"
    t.string "priority_jabvox", default: "normal", null: false
    t.string "status_jabvox", default: "open", null: false
    t.datetime "due_at_jabvox"
    t.integer "position_jabvox", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "due_dates_jabvox", default: [], null: false
    t.bigint "contact_id"
    t.string "recurrence_unit_jabvox"
    t.integer "recurrence_count_jabvox", default: 1, null: false
    t.datetime "recurrence_until_jabvox"
    t.bigint "recurrence_parent_id"
    t.datetime "reminder_sent_at_jabvox"
    t.bigint "source_task_id"
    t.index ["account_id", "board_id"], name: "index_jabvox_tasks_on_account_id_and_board_id"
    t.index ["account_id", "contact_id"], name: "index_jabvox_tasks_on_account_id_and_contact_id"
    t.index ["account_id", "due_at_jabvox"], name: "index_jabvox_tasks_on_account_id_and_due_at_jabvox"
    t.index ["account_id", "recurrence_unit_jabvox"], name: "index_jabvox_tasks_on_account_and_recurrence", where: "(recurrence_unit_jabvox IS NOT NULL)"
    t.index ["account_id"], name: "index_jabvox_tasks_on_account_id"
    t.index ["assignee_id"], name: "index_jabvox_tasks_on_assignee_id"
    t.index ["board_id"], name: "index_jabvox_tasks_on_board_id"
    t.index ["created_by_id"], name: "index_jabvox_tasks_on_created_by_id"
    t.index ["recurrence_parent_id"], name: "index_jabvox_tasks_on_recurrence_parent_id"
    t.index ["source_task_id"], name: "index_jabvox_tasks_on_source_task_id"
    t.index ["stage_id", "position_jabvox"], name: "index_jabvox_tasks_on_stage_id_and_position_jabvox"
    t.index ["stage_id"], name: "index_jabvox_tasks_on_stage_id"
  end

  create_table "jabvox_tax_rates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.decimal "percentage_jabvox", precision: 5, scale: 2, default: "0.0", null: false
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_tax_rates_account_name", unique: true
    t.index ["account_id"], name: "index_jabvox_tax_rates_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_tax_rates_on_created_by_id"
  end

  create_table "jabvox_ticket_activities", force: :cascade do |t|
    t.integer "ticket_id", null: false
    t.integer "user_id"
    t.string "action_jabvox", null: false
    t.string "from_value_jabvox"
    t.string "to_value_jabvox"
    t.jsonb "metadata_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "idx_ticket_activities_ticket"
  end

  create_table "jabvox_ticket_categories", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "responsible_id"
    t.string "name_jabvox", null: false
    t.integer "category_type_jabvox", default: 0, null: false
    t.string "color_jabvox", default: "#1F93FF", null: false
    t.text "description_jabvox"
    t.integer "sla_response_minutes_jabvox", default: 60, null: false
    t.integer "sla_resolution_minutes_jabvox", default: 1440, null: false
    t.integer "position_jabvox", default: 0, null: false
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "parent_id"
    t.index ["account_id", "active_jabvox"], name: "idx_ticket_categories_account_active"
    t.index ["account_id", "parent_id"], name: "idx_ticket_categories_account_parent"
    t.index ["account_id"], name: "idx_ticket_categories_account"
  end

  create_table "jabvox_ticket_comments", force: :cascade do |t|
    t.integer "ticket_id", null: false
    t.integer "user_id", null: false
    t.text "body_jabvox", null: false
    t.boolean "private_jabvox", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id", "created_at"], name: "idx_ticket_comments_ticket_created"
    t.index ["ticket_id"], name: "idx_ticket_comments_ticket"
  end

  create_table "jabvox_ticket_helpdesk_configs", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "auto_assign_mode_jabvox", default: 0, null: false
    t.boolean "active_jabvox", default: true, null: false
    t.jsonb "settings_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "business_hours_jabvox", default: {}, null: false
    t.integer "resolver_visibility_jabvox", default: 0, null: false
    t.index ["account_id"], name: "idx_ticket_helpdesk_account", unique: true
  end

  create_table "jabvox_tickets", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "display_id_jabvox", null: false
    t.string "title_jabvox", null: false
    t.text "description_jabvox"
    t.integer "ticket_category_id"
    t.integer "category_type_jabvox", default: 0, null: false
    t.integer "priority_jabvox", default: 1, null: false
    t.integer "status_jabvox", default: 0, null: false
    t.integer "requester_id", null: false
    t.integer "assignee_id"
    t.integer "conversation_id"
    t.integer "contact_id"
    t.datetime "due_at_jabvox"
    t.datetime "first_response_at_jabvox"
    t.datetime "resolved_at_jabvox"
    t.datetime "closed_at_jabvox"
    t.text "resolution_jabvox"
    t.integer "resolution_type_jabvox"
    t.integer "satisfaction_rating_jabvox"
    t.text "satisfaction_comment_jabvox"
    t.integer "reopened_count_jabvox", default: 0, null: false
    t.jsonb "custom_attributes_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "sla_escalated_at_jabvox"
    t.datetime "sla_warned_at_jabvox"
    t.integer "lock_version", default: 0, null: false
    t.integer "comments_count_jabvox", default: 0, null: false
    t.datetime "deleted_at_jabvox"
    t.virtual "search_vector_jabvox", type: :tsvector, as: "(setweight(to_tsvector('simple'::regconfig, jabvox_immutable_unaccent((COALESCE(title_jabvox, ''::character varying))::text)), 'A'::\"char\") || setweight(to_tsvector('simple'::regconfig, jabvox_immutable_unaccent(COALESCE(description_jabvox, ''::text))), 'B'::\"char\"))", stored: true
    t.index ["account_id", "assignee_id"], name: "idx_tickets_account_assignee"
    t.index ["account_id", "category_type_jabvox"], name: "idx_tickets_account_ctype"
    t.index ["account_id", "deleted_at_jabvox"], name: "idx_tickets_account_deleted"
    t.index ["account_id", "display_id_jabvox"], name: "idx_tickets_account_display", unique: true
    t.index ["account_id", "due_at_jabvox"], name: "idx_tickets_open_due", where: "((status_jabvox <> ALL (ARRAY[4, 5])) AND (deleted_at_jabvox IS NULL))"
    t.index ["account_id", "requester_id"], name: "idx_tickets_account_requester"
    t.index ["account_id", "status_jabvox"], name: "idx_tickets_account_status"
    t.index ["due_at_jabvox"], name: "idx_tickets_sla_pending", where: "((status_jabvox <> ALL (ARRAY[4, 5])) AND (sla_escalated_at_jabvox IS NULL) AND (deleted_at_jabvox IS NULL))"
    t.index ["search_vector_jabvox"], name: "idx_tickets_search_vector", using: :gin
  end

  create_table "jabvox_typifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "description", default: "", null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "name"], name: "index_jabvox_typifications_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_jabvox_typifications_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_typifications_on_created_by_id"
  end

  create_table "jabvox_units_of_measure", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name_jabvox", null: false
    t.string "abbreviation_jabvox"
    t.boolean "active_jabvox", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["account_id", "name_jabvox"], name: "index_jabvox_units_account_name", unique: true
    t.index ["account_id"], name: "index_jabvox_units_of_measure_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_units_of_measure_on_created_by_id"
  end

  create_table "jabvox_user_extensions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "extension_jabvox", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "extension_jabvox"], name: "idx_user_extensions_on_account_ext", unique: true
    t.index ["account_id", "user_id"], name: "idx_user_extensions_on_account_user", unique: true
    t.index ["account_id"], name: "index_jabvox_user_extensions_on_account_id"
    t.index ["user_id"], name: "index_jabvox_user_extensions_on_user_id"
  end

  create_table "jabvox_voice_broadcast_audits", force: :cascade do |t|
    t.bigint "jabvox_voice_broadcast_id", null: false
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "action_jabvox", null: false
    t.jsonb "metadata_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "idx_vba_account_time"
    t.index ["jabvox_voice_broadcast_id"], name: "idx_vba_broadcast"
  end

  create_table "jabvox_voice_broadcast_call_logs", force: :cascade do |t|
    t.bigint "jabvox_voice_broadcast_id", null: false
    t.bigint "jabvox_voice_broadcast_recipient_id", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id"
    t.string "phone_jabvox", null: false
    t.string "name_jabvox"
    t.integer "attempt_number_jabvox", default: 1, null: false
    t.string "outcome_jabvox"
    t.string "amd_status_jabvox"
    t.string "dtmf_pressed_jabvox"
    t.boolean "played_full_jabvox", default: false, null: false
    t.integer "duration_ms_jabvox"
    t.string "recording_file_jabvox"
    t.string "uniqueid_jabvox"
    t.string "linkedid_jabvox"
    t.string "hangup_cause_jabvox"
    t.datetime "started_at_jabvox"
    t.datetime "ended_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "answered_at_jabvox"
    t.integer "ring_ms_jabvox"
    t.integer "total_duration_ms_jabvox"
    t.index ["account_id", "created_at"], name: "idx_vb_call_logs_account_created"
    t.index ["jabvox_voice_broadcast_id"], name: "idx_vb_call_logs_broadcast"
    t.index ["jabvox_voice_broadcast_recipient_id"], name: "idx_vb_call_logs_recipient"
    t.index ["uniqueid_jabvox"], name: "idx_vb_call_logs_uniqueid"
  end

  create_table "jabvox_voice_broadcast_recipients", force: :cascade do |t|
    t.bigint "jabvox_voice_broadcast_id", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id"
    t.string "phone_jabvox", null: false
    t.string "name_jabvox"
    t.string "status_jabvox", default: "pending", null: false
    t.string "outcome_jabvox"
    t.string "amd_status_jabvox"
    t.boolean "played_full_jabvox", default: false, null: false
    t.string "dtmf_pressed_jabvox"
    t.integer "duration_ms_jabvox"
    t.integer "attempts_jabvox", default: 0, null: false
    t.datetime "last_attempt_at_jabvox"
    t.string "recording_file_jabvox"
    t.string "uniqueid_jabvox"
    t.string "linkedid_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "answered_at_jabvox"
    t.integer "ring_ms_jabvox"
    t.index ["account_id", "uniqueid_jabvox"], name: "idx_vbr_account_uniqueid", where: "(uniqueid_jabvox IS NOT NULL)"
    t.index ["account_id"], name: "idx_vbr_account"
    t.index ["jabvox_voice_broadcast_id", "phone_jabvox"], name: "idx_vbr_unique_phone", unique: true
    t.index ["jabvox_voice_broadcast_id", "status_jabvox"], name: "idx_vbr_broadcast_status"
    t.index ["jabvox_voice_broadcast_id"], name: "idx_vbr_broadcast"
  end

  create_table "jabvox_voice_broadcasts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_dialer_campaign_id"
    t.bigint "created_by_id"
    t.string "name_jabvox", default: "", null: false
    t.string "status_jabvox", default: "draft", null: false
    t.string "audio_filename_jabvox"
    t.string "audio_original_name_jabvox"
    t.integer "audio_duration_ms_jabvox"
    t.boolean "audio_deployed_jabvox", default: false, null: false
    t.string "caller_id_jabvox", default: "", null: false
    t.integer "max_concurrent_jabvox", default: 5, null: false
    t.integer "cps_jabvox", default: 1, null: false
    t.integer "max_retries_jabvox", default: 0, null: false
    t.integer "retry_interval_jabvox", default: 300, null: false
    t.boolean "amd_enabled_jabvox", default: true, null: false
    t.boolean "dtmf_enabled_jabvox", default: false, null: false
    t.string "dtmf_optout_digit_jabvox", default: "9"
    t.string "calling_hours_start_jabvox"
    t.string "calling_hours_end_jabvox"
    t.integer "total_recipients_jabvox", default: 0, null: false
    t.integer "dialed_count_jabvox", default: 0, null: false
    t.integer "answered_human_count_jabvox", default: 0, null: false
    t.integer "answered_machine_count_jabvox", default: 0, null: false
    t.integer "played_complete_count_jabvox", default: 0, null: false
    t.integer "failed_count_jabvox", default: 0, null: false
    t.datetime "started_at_jabvox"
    t.datetime "finished_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "countries_jabvox"
    t.jsonb "management_state_ids_jabvox"
    t.jsonb "affiliate_ids_jabvox"
    t.jsonb "inbox_ids_jabvox"
    t.jsonb "excluded_lead_ids_jabvox", default: [], null: false
    t.jsonb "lead_filters_jabvox", default: {}, null: false
    t.bigint "jabvox_campaign_id"
    t.string "source_jabvox", default: "campaign", null: false
    t.index ["account_id", "status_jabvox"], name: "idx_vb_account_status"
    t.index ["account_id"], name: "idx_vb_account"
    t.index ["jabvox_dialer_campaign_id"], name: "idx_vb_campaign"
  end

  create_table "jabvox_voip_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "host", default: "", null: false
    t.integer "port", default: 5038, null: false
    t.string "username", default: "", null: false
    t.text "password"
    t.string "context", default: "clicktocall", null: false
    t.string "dialer_context", default: ""
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "dialer_trunk", default: "", null: false
    t.string "dialer_caller_id", default: "", null: false
    t.string "dial_field_jabvox"
    t.string "dial_prefix_jabvox"
    t.string "dialer_provider_prefix", default: "", null: false
    t.index ["account_id"], name: "index_jabvox_voip_configs_on_account_id", unique: true
  end

  create_table "jabvox_whatsapp_flow_answers", force: :cascade do |t|
    t.bigint "jabvox_whatsapp_flow_submission_id", null: false
    t.string "screen_id", null: false
    t.string "component_id", null: false
    t.string "component_name", null: false
    t.string "component_type", null: false
    t.text "value_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["component_name"], name: "index_jabvox_whatsapp_flow_answers_on_component_name"
    t.index ["jabvox_whatsapp_flow_submission_id"], name: "idx_jabvox_wa_flow_answers_on_submission_id"
  end

  create_table "jabvox_whatsapp_flow_submissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "jabvox_whatsapp_flow_id", null: false
    t.integer "jabvox_whatsapp_flow_version", null: false
    t.bigint "contact_id", null: false
    t.bigint "conversation_id"
    t.bigint "message_id"
    t.string "flow_token", null: false
    t.string "status", default: "completed", null: false
    t.jsonb "raw_response_json", default: {}, null: false
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "flow_token"], name: "idx_jabvox_wa_flow_subs_account_flow_token", unique: true
    t.index ["account_id", "jabvox_whatsapp_flow_id"], name: "idx_jabvox_wa_flow_subs_account_flow"
    t.index ["account_id"], name: "index_jabvox_whatsapp_flow_submissions_on_account_id"
    t.index ["contact_id"], name: "index_jabvox_whatsapp_flow_submissions_on_contact_id"
    t.index ["conversation_id"], name: "index_jabvox_whatsapp_flow_submissions_on_conversation_id"
    t.index ["jabvox_whatsapp_flow_id"], name: "idx_on_jabvox_whatsapp_flow_id_750a893b45"
    t.index ["message_id"], name: "index_jabvox_whatsapp_flow_submissions_on_message_id"
  end

  create_table "jabvox_whatsapp_flow_versions", force: :cascade do |t|
    t.bigint "jabvox_whatsapp_flow_id", null: false
    t.integer "version", default: 1, null: false
    t.jsonb "screens_json", default: [], null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_jabvox_whatsapp_flow_versions_on_created_by_id"
    t.index ["jabvox_whatsapp_flow_id", "version"], name: "idx_jabvox_wa_flow_versions_flow_version"
    t.index ["jabvox_whatsapp_flow_id"], name: "index_jabvox_whatsapp_flow_versions_on_jabvox_whatsapp_flow_id"
  end

  create_table "jabvox_whatsapp_flows", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.string "waba_id", null: false
    t.string "name", null: false
    t.string "category", null: false
    t.text "description"
    t.string "status", default: "draft", null: false
    t.string "meta_flow_id"
    t.string "meta_status"
    t.jsonb "screens_json", default: [], null: false
    t.jsonb "validation_errors_json", default: [], null: false
    t.jsonb "meta_json", default: {}, null: false
    t.datetime "published_at"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "meta_flow_id"], name: "idx_jabvox_wa_flows_account_meta_flow_id"
    t.index ["account_id", "name"], name: "idx_jabvox_wa_flows_account_name"
    t.index ["account_id"], name: "index_jabvox_whatsapp_flows_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_whatsapp_flows_on_created_by_id"
    t.index ["inbox_id"], name: "index_jabvox_whatsapp_flows_on_inbox_id"
    t.index ["status"], name: "index_jabvox_whatsapp_flows_on_status"
  end

  create_table "jabvox_whatsapp_group_members", force: :cascade do |t|
    t.integer "whatsapp_group_id", null: false
    t.integer "account_id", null: false
    t.integer "contact_id"
    t.string "phone_number_jabvox", null: false
    t.string "name_jabvox"
    t.string "role_jabvox", default: "member", null: false
    t.string "invite_status_jabvox", default: "pending", null: false
    t.datetime "joined_at_jabvox"
    t.datetime "left_at_jabvox"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["whatsapp_group_id", "phone_number_jabvox"], name: "idx_wa_group_members_unique", unique: true
    t.index ["whatsapp_group_id"], name: "idx_wa_group_members_group"
  end

  create_table "jabvox_whatsapp_groups", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "conversation_id"
    t.integer "created_by_id"
    t.string "provider_group_id_jabvox"
    t.string "name_jabvox", null: false
    t.text "description_jabvox"
    t.string "avatar_url_jabvox"
    t.text "invite_link_jabvox"
    t.string "status_jabvox", default: "active", null: false
    t.jsonb "metadata_jabvox", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "idx_wa_groups_account"
    t.index ["inbox_id"], name: "idx_wa_groups_inbox"
    t.index ["provider_group_id_jabvox"], name: "idx_wa_groups_provider_id", unique: true, where: "(provider_group_id_jabvox IS NOT NULL)"
  end

  create_table "jabvox_whatsapp_template_logs", force: :cascade do |t|
    t.bigint "jabvox_whatsapp_template_id", null: false
    t.bigint "account_id", null: false
    t.string "action", null: false
    t.text "description"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jabvox_whatsapp_template_logs_on_account_id"
    t.index ["action"], name: "index_jabvox_whatsapp_template_logs_on_action"
    t.index ["jabvox_whatsapp_template_id"], name: "idx_on_jabvox_whatsapp_template_id_476ec4a376"
    t.index ["user_id"], name: "index_jabvox_whatsapp_template_logs_on_user_id"
  end

  create_table "jabvox_whatsapp_template_permissions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.boolean "can_manage", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "idx_jabvox_wa_template_perms_account_user", unique: true
    t.index ["account_id"], name: "index_jabvox_whatsapp_template_permissions_on_account_id"
    t.index ["user_id"], name: "index_jabvox_whatsapp_template_permissions_on_user_id"
  end

  create_table "jabvox_whatsapp_template_versions", force: :cascade do |t|
    t.bigint "jabvox_whatsapp_template_id", null: false
    t.integer "version", default: 1, null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_jabvox_whatsapp_template_versions_on_created_by_id"
    t.index ["jabvox_whatsapp_template_id", "version"], name: "idx_jabvox_wa_tpl_versions_tpl_version"
    t.index ["jabvox_whatsapp_template_id"], name: "idx_on_jabvox_whatsapp_template_id_e80a5f5da4"
  end

  create_table "jabvox_whatsapp_templates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.string "meta_template_id"
    t.string "waba_id"
    t.string "phone_number_id"
    t.string "name", null: false
    t.string "language", default: "es", null: false
    t.string "category", default: "UTILITY", null: false
    t.string "status", default: "PENDING", null: false
    t.string "quality_score"
    t.string "header_type"
    t.text "header_content"
    t.text "body_content"
    t.text "footer_content"
    t.jsonb "buttons_json", default: [], null: false
    t.jsonb "variables_json", default: {}, null: false
    t.jsonb "meta_json", default: {}, null: false
    t.string "rejected_reason"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "template_kind", default: "standard", null: false
    t.jsonb "cards_json", default: [], null: false
    t.jsonb "auth_config_json", default: {}, null: false
    t.boolean "location_header", default: false, null: false
    t.boolean "limited_time_offer", default: false, null: false
    t.bigint "jabvox_whatsapp_flow_id"
    t.index ["account_id", "name", "language"], name: "idx_jabvox_wa_templates_account_name_lang"
    t.index ["account_id"], name: "index_jabvox_whatsapp_templates_on_account_id"
    t.index ["created_by_id"], name: "index_jabvox_whatsapp_templates_on_created_by_id"
    t.index ["inbox_id"], name: "index_jabvox_whatsapp_templates_on_inbox_id"
    t.index ["jabvox_whatsapp_flow_id"], name: "index_jabvox_whatsapp_templates_on_jabvox_whatsapp_flow_id"
    t.index ["meta_template_id"], name: "index_jabvox_whatsapp_templates_on_meta_template_id"
    t.index ["status"], name: "index_jabvox_whatsapp_templates_on_status"
    t.index ["template_kind"], name: "index_jabvox_whatsapp_templates_on_template_kind"
  end

  create_table "labels", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "color", default: "#1f93ff", null: false
    t.boolean "show_on_sidebar"
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_labels_on_account_id"
    t.index ["title", "account_id"], name: "index_labels_on_title_and_account_id", unique: true
  end

  create_table "leaves", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "leave_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_leaves_on_account_id_and_status"
    t.index ["account_id"], name: "index_leaves_on_account_id"
    t.index ["approved_by_id"], name: "index_leaves_on_approved_by_id"
    t.index ["user_id"], name: "index_leaves_on_user_id"
  end

  create_table "macros", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "visibility", default: 0
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.jsonb "actions", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_macros_on_account_id"
  end

  create_table "mentions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.datetime "mentioned_at", precision: nil, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_mentions_on_account_id"
    t.index ["conversation_id"], name: "index_mentions_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_mentions_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_mentions_on_user_id"
  end

  create_table "message_status_events", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "account_id", null: false
    t.bigint "conversation_id"
    t.bigint "inbox_id"
    t.integer "status", null: false
    t.datetime "occurred_at", null: false
    t.string "error_code"
    t.string "error_title"
    t.datetime "created_at", null: false
    t.string "pricing_category"
    t.boolean "pricing_billable"
    t.string "pricing_model"
    t.string "whatsapp_conversation_id"
    t.string "conversation_origin_type"
    t.index ["account_id", "occurred_at"], name: "idx_message_status_events_account_time"
    t.index ["account_id", "pricing_category"], name: "idx_message_status_events_account_pricing"
    t.index ["inbox_id"], name: "idx_message_status_events_inbox"
    t.index ["message_id", "status"], name: "idx_message_status_events_unique", unique: true
  end

  create_table "messages", id: :serial, force: :cascade do |t|
    t.text "content"
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "conversation_id", null: false
    t.integer "message_type", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "private", default: false, null: false
    t.integer "status", default: 0
    t.text "source_id"
    t.integer "content_type", default: 0, null: false
    t.json "content_attributes", default: {}
    t.string "sender_type"
    t.bigint "sender_id"
    t.jsonb "external_source_ids", default: {}
    t.jsonb "additional_attributes", default: {}
    t.text "processed_message_content"
    t.jsonb "sentiment", default: {}
    t.index "((additional_attributes -> 'campaign_id'::text))", name: "index_messages_on_additional_attributes_campaign_id", using: :gin
    t.index ["account_id", "content_type", "created_at"], name: "idx_messages_account_content_created"
    t.index ["account_id", "created_at", "message_type"], name: "index_messages_on_account_created_type"
    t.index ["account_id", "inbox_id"], name: "index_messages_on_account_id_and_inbox_id"
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["content"], name: "index_messages_on_content", opclass: :gin_trgm_ops, using: :gin
    t.index ["conversation_id", "account_id", "message_type", "created_at"], name: "index_messages_on_conversation_account_type_created"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["inbox_id"], name: "index_messages_on_inbox_id"
    t.index ["sender_type", "sender_id", "created_at"], name: "index_messages_on_sender_and_created"
    t.index ["sender_type", "sender_id"], name: "index_messages_on_sender_type_and_sender_id"
    t.index ["source_id"], name: "index_messages_on_source_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "content_attributes", default: {}
    t.index ["account_id"], name: "index_notes_on_account_id"
    t.index ["contact_id"], name: "index_notes_on_contact_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notification_settings", force: :cascade do |t|
    t.integer "account_id"
    t.integer "user_id"
    t.integer "email_flags", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "push_flags", default: 0, null: false
    t.index ["account_id", "user_id"], name: "by_account_user", unique: true
  end

  create_table "notification_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "subscription_type", null: false
    t.jsonb "subscription_attributes", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "identifier"
    t.index ["identifier"], name: "index_notification_subscriptions_on_identifier", unique: true
    t.index ["user_id"], name: "index_notification_subscriptions_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.integer "notification_type", null: false
    t.string "primary_actor_type", null: false
    t.bigint "primary_actor_id", null: false
    t.string "secondary_actor_type"
    t.bigint "secondary_actor_id"
    t.datetime "read_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "snoozed_until"
    t.datetime "last_activity_at", default: -> { "CURRENT_TIMESTAMP" }
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_notifications_on_account_id"
    t.index ["last_activity_at"], name: "index_notifications_on_last_activity_at"
    t.index ["primary_actor_type", "primary_actor_id"], name: "uniq_primary_actor_per_account_notifications"
    t.index ["secondary_actor_type", "secondary_actor_id"], name: "uniq_secondary_actor_per_account_notifications"
    t.index ["user_id", "account_id", "snoozed_until", "read_at"], name: "idx_notifications_performance"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "platform_app_permissibles", force: :cascade do |t|
    t.bigint "platform_app_id", null: false
    t.string "permissible_type", null: false
    t.bigint "permissible_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permissible_type", "permissible_id"], name: "index_platform_app_permissibles_on_permissibles"
    t.index ["platform_app_id", "permissible_id", "permissible_type"], name: "unique_permissibles_index", unique: true
    t.index ["platform_app_id"], name: "index_platform_app_permissibles_on_platform_app_id"
  end

  create_table "platform_apps", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "platform_banners", force: :cascade do |t|
    t.text "banner_message", null: false
    t.integer "banner_type", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "portals", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "custom_domain"
    t.string "color"
    t.string "homepage_link"
    t.string "page_title"
    t.text "header_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "config", default: {"allowed_locales" => ["en"]}
    t.boolean "archived", default: false
    t.bigint "channel_web_widget_id"
    t.jsonb "ssl_settings", default: {}, null: false
    t.index ["channel_web_widget_id"], name: "index_portals_on_channel_web_widget_id"
    t.index ["custom_domain"], name: "index_portals_on_custom_domain", unique: true
    t.index ["slug"], name: "index_portals_on_slug", unique: true
  end

  create_table "portals_members", id: false, force: :cascade do |t|
    t.bigint "portal_id", null: false
    t.bigint "user_id", null: false
    t.index ["portal_id", "user_id"], name: "index_portals_members_on_portal_id_and_user_id", unique: true
    t.index ["portal_id"], name: "index_portals_members_on_portal_id"
    t.index ["user_id"], name: "index_portals_members_on_user_id"
  end

  create_table "related_categories", force: :cascade do |t|
    t.bigint "category_id"
    t.bigint "related_category_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "related_category_id"], name: "index_related_categories_on_category_id_and_related_category_id", unique: true
    t.index ["related_category_id", "category_id"], name: "index_related_categories_on_related_category_id_and_category_id", unique: true
  end

  create_table "reporting_events", force: :cascade do |t|
    t.string "name"
    t.float "value"
    t.integer "account_id"
    t.integer "inbox_id"
    t.integer "user_id"
    t.integer "conversation_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "value_in_business_hours"
    t.datetime "event_start_time", precision: nil
    t.datetime "event_end_time", precision: nil
    t.index ["account_id", "name", "created_at"], name: "reporting_events__account_id__name__created_at"
    t.index ["account_id", "name", "inbox_id", "created_at"], name: "index_reporting_events_for_response_distribution"
    t.index ["account_id"], name: "index_reporting_events_on_account_id"
    t.index ["conversation_id"], name: "index_reporting_events_on_conversation_id"
    t.index ["created_at"], name: "index_reporting_events_on_created_at"
    t.index ["inbox_id"], name: "index_reporting_events_on_inbox_id"
    t.index ["name"], name: "index_reporting_events_on_name"
    t.index ["user_id"], name: "index_reporting_events_on_user_id"
  end

  create_table "reporting_events_rollups", force: :cascade do |t|
    t.integer "account_id", null: false
    t.date "date", null: false
    t.string "dimension_type", null: false
    t.bigint "dimension_id", null: false
    t.string "metric", null: false
    t.bigint "count", default: 0, null: false
    t.float "sum_value", default: 0.0, null: false
    t.float "sum_value_business_hours", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "date", "dimension_type", "dimension_id", "metric"], name: "index_rollup_unique_key", unique: true
    t.index ["account_id", "dimension_type", "date"], name: "index_rollup_summary"
    t.index ["account_id", "metric", "date"], name: "index_rollup_timeseries"
  end

  create_table "sla_events", force: :cascade do |t|
    t.bigint "applied_sla_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "event_type"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sla_events_on_account_id"
    t.index ["applied_sla_id"], name: "index_sla_events_on_applied_sla_id"
    t.index ["conversation_id"], name: "index_sla_events_on_conversation_id"
    t.index ["inbox_id"], name: "index_sla_events_on_inbox_id"
    t.index ["sla_policy_id"], name: "index_sla_events_on_sla_policy_id"
  end

  create_table "sla_policies", force: :cascade do |t|
    t.string "name", null: false
    t.float "first_response_time_threshold"
    t.float "next_response_time_threshold"
    t.boolean "only_during_business_hours", default: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.float "resolution_time_threshold"
    t.index ["account_id"], name: "index_sla_policies_on_account_id"
  end

  create_table "taggings", id: :serial, force: :cascade do |t|
    t.integer "tag_id"
    t.string "taggable_type"
    t.integer "taggable_id"
    t.string "tagger_type"
    t.integer "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "index_taggings_on_taggable_id_and_taggable_type_and_context"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
  end

  create_table "tags", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "taggings_count", default: 0
    t.index "lower((name)::text) gin_trgm_ops", name: "tags_name_trgm_idx", using: :gin
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "team_members", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "allow_auto_assign", default: true
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "icon", default: ""
    t.string "icon_color", default: ""
    t.index ["account_id"], name: "index_teams_on_account_id"
    t.index ["name", "account_id"], name: "index_teams_on_name_and_account_id", unique: true
  end

  create_table "user_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "client_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.string "browser_name"
    t.string "browser_version"
    t.string "device_name"
    t.string "platform_name"
    t.string "platform_version"
    t.string "city"
    t.string "country"
    t.string "country_code"
    t.datetime "last_activity_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "client_id"], name: "index_user_sessions_on_user_id_and_client_id", unique: true
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "provider", default: "email", null: false
    t.string "uid", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.string "unconfirmed_email"
    t.string "name", null: false
    t.string "display_name"
    t.string "email"
    t.json "tokens"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "pubsub_token"
    t.integer "availability", default: 0
    t.jsonb "ui_settings", default: {}
    t.jsonb "custom_attributes", default: {}
    t.string "type"
    t.text "message_signature"
    t.string "otp_secret"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login", default: false
    t.text "otp_backup_codes"
    t.boolean "can_view_access_token_jabvox", default: false, null: false
    t.index ["email"], name: "index_users_on_email"
    t.index ["otp_required_for_login"], name: "index_users_on_otp_required_for_login"
    t.index ["otp_secret"], name: "index_users_on_otp_secret", unique: true
    t.index ["pubsub_token"], name: "index_users_on_pubsub_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["uid", "provider"], name: "index_users_on_uid_and_provider", unique: true
  end

  create_table "webhooks", force: :cascade do |t|
    t.integer "account_id"
    t.integer "inbox_id"
    t.text "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "webhook_type", default: 0
    t.jsonb "subscriptions", default: ["conversation_status_changed", "conversation_updated", "conversation_created", "contact_created", "contact_updated", "message_created", "message_updated", "webwidget_triggered"]
    t.string "name"
    t.string "secret"
    t.jsonb "conditions", default: {}, null: false
    t.index ["account_id", "url"], name: "index_webhooks_on_account_id_and_url", unique: true
  end

  create_table "working_hours", force: :cascade do |t|
    t.bigint "inbox_id"
    t.bigint "account_id"
    t.integer "day_of_week", null: false
    t.boolean "closed_all_day", default: false
    t.integer "open_hour"
    t.integer "open_minutes"
    t.integer "close_hour"
    t.integer "close_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "open_all_day", default: false
    t.index ["account_id"], name: "index_working_hours_on_account_id"
    t.index ["inbox_id"], name: "index_working_hours_on_inbox_id"
  end

  add_foreign_key "account_automation_configs", "accounts"
  add_foreign_key "account_automation_configs", "users", column: "automations_user_id", on_delete: :nullify
  add_foreign_key "account_users", "jabvox_app_states", on_delete: :nullify
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "inboxes", "portals"
  add_foreign_key "jabvox_affiliate_imports", "accounts"
  add_foreign_key "jabvox_affiliate_imports", "jabvox_affiliates"
  add_foreign_key "jabvox_affiliate_imports", "users", column: "created_by_id"
  add_foreign_key "jabvox_affiliate_ip_whitelists", "jabvox_affiliates"
  add_foreign_key "jabvox_affiliates", "accounts"
  add_foreign_key "jabvox_agent_availabilities", "accounts"
  add_foreign_key "jabvox_agent_availabilities", "jabvox_branches", column: "branch_id"
  add_foreign_key "jabvox_agent_availabilities", "users"
  add_foreign_key "jabvox_ai_balance_movements", "accounts"
  add_foreign_key "jabvox_ai_chat_configs", "accounts"
  add_foreign_key "jabvox_ai_chat_configs", "jabvox_ai_chat_storages", column: "documents_storage_jabvox_id", on_delete: :nullify
  add_foreign_key "jabvox_ai_chat_documents", "accounts"
  add_foreign_key "jabvox_ai_chat_documents", "users", column: "created_by_id"
  add_foreign_key "jabvox_ai_chat_messages", "accounts"
  add_foreign_key "jabvox_ai_chat_messages", "users"
  add_foreign_key "jabvox_ai_chat_models", "accounts"
  add_foreign_key "jabvox_ai_chat_models", "jabvox_hermes_agents", column: "hermes_agent_id"
  add_foreign_key "jabvox_ai_chat_sessions", "accounts"
  add_foreign_key "jabvox_ai_chat_sessions", "users"
  add_foreign_key "jabvox_ai_chat_user_permissions", "accounts"
  add_foreign_key "jabvox_ai_chat_user_permissions", "users"
  add_foreign_key "jabvox_ai_provider_accounts", "accounts"
  add_foreign_key "jabvox_analytics_audit_logs", "accounts"
  add_foreign_key "jabvox_analytics_audit_logs", "users"
  add_foreign_key "jabvox_analytics_cross_joins", "jabvox_analytics_cross_reports", column: "cross_report_id"
  add_foreign_key "jabvox_analytics_cross_joins", "jabvox_analytics_cross_sources", column: "left_source_id"
  add_foreign_key "jabvox_analytics_cross_joins", "jabvox_analytics_cross_sources", column: "right_source_id"
  add_foreign_key "jabvox_analytics_cross_reports", "accounts"
  add_foreign_key "jabvox_analytics_cross_reports", "users", column: "created_by_id"
  add_foreign_key "jabvox_analytics_cross_sources", "jabvox_analytics_cross_reports", column: "cross_report_id"
  add_foreign_key "jabvox_analytics_cross_sources", "jabvox_analytics_data_sources", column: "data_source_id"
  add_foreign_key "jabvox_analytics_dashboard_widgets", "accounts"
  add_foreign_key "jabvox_analytics_dashboard_widgets", "jabvox_analytics_dashboards", column: "dashboard_id"
  add_foreign_key "jabvox_analytics_dashboard_widgets", "jabvox_analytics_data_sources", column: "data_source_id"
  add_foreign_key "jabvox_analytics_dashboard_widgets", "users", column: "created_by_id"
  add_foreign_key "jabvox_analytics_dashboards", "accounts"
  add_foreign_key "jabvox_analytics_dashboards", "jabvox_analytics_folders", column: "folder_id"
  add_foreign_key "jabvox_analytics_dashboards", "users", column: "created_by_id"
  add_foreign_key "jabvox_analytics_data_source_permissions", "accounts"
  add_foreign_key "jabvox_analytics_data_source_permissions", "jabvox_analytics_data_sources", column: "data_source_id"
  add_foreign_key "jabvox_analytics_data_source_permissions", "jabvox_analytics_roles", column: "role_id"
  add_foreign_key "jabvox_analytics_data_source_permissions", "users"
  add_foreign_key "jabvox_analytics_data_sources", "accounts"
  add_foreign_key "jabvox_analytics_data_sources", "users", column: "created_by_id"
  add_foreign_key "jabvox_analytics_exports", "accounts"
  add_foreign_key "jabvox_analytics_exports", "jabvox_analytics_dashboards", column: "dashboard_id"
  add_foreign_key "jabvox_analytics_exports", "users"
  add_foreign_key "jabvox_analytics_folders", "accounts"
  add_foreign_key "jabvox_analytics_folders", "jabvox_analytics_folders", column: "parent_id"
  add_foreign_key "jabvox_analytics_folders", "users", column: "created_by_id"
  add_foreign_key "jabvox_analytics_permissions", "accounts"
  add_foreign_key "jabvox_analytics_permissions", "jabvox_analytics_roles", column: "role_id"
  add_foreign_key "jabvox_analytics_permissions", "users", column: "created_by_id"
  add_foreign_key "jabvox_analytics_query_cache", "accounts"
  add_foreign_key "jabvox_analytics_query_cache", "jabvox_analytics_data_sources", column: "data_source_id"
  add_foreign_key "jabvox_analytics_roles", "accounts"
  add_foreign_key "jabvox_analytics_roles", "users", column: "created_by_id"
  add_foreign_key "jabvox_analytics_shares", "accounts"
  add_foreign_key "jabvox_analytics_shares", "jabvox_analytics_dashboards", column: "dashboard_id"
  add_foreign_key "jabvox_analytics_shares", "users", column: "created_by_id"
  add_foreign_key "jabvox_analytics_user_permissions", "accounts"
  add_foreign_key "jabvox_analytics_user_permissions", "jabvox_analytics_roles", column: "role_id"
  add_foreign_key "jabvox_analytics_user_permissions", "users"
  add_foreign_key "jabvox_analytics_widget_filters", "accounts"
  add_foreign_key "jabvox_analytics_widget_filters", "jabvox_analytics_dashboard_widgets", column: "widget_id"
  add_foreign_key "jabvox_analytics_widget_filters", "jabvox_analytics_dashboards", column: "dashboard_id"
  add_foreign_key "jabvox_analytics_widget_filters", "users", column: "created_by_id"
  add_foreign_key "jabvox_app_state_logs", "accounts"
  add_foreign_key "jabvox_app_states", "accounts"
  add_foreign_key "jabvox_app_states", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_advisors", "accounts"
  add_foreign_key "jabvox_audio_advisors", "users"
  add_foreign_key "jabvox_audio_advisors", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_anatomy_criteria", "accounts"
  add_foreign_key "jabvox_audio_anatomy_criteria", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_assignments", "accounts"
  add_foreign_key "jabvox_audio_assignments", "jabvox_audio_storages", column: "storage_id"
  add_foreign_key "jabvox_audio_assignments", "jabvox_typifications", column: "typification_id"
  add_foreign_key "jabvox_audio_assignments", "users", column: "agent_id"
  add_foreign_key "jabvox_audio_assignments", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_code_mappings", "accounts"
  add_foreign_key "jabvox_audio_code_mappings", "jabvox_audio_advisors", column: "advisor_id"
  add_foreign_key "jabvox_audio_code_mappings", "jabvox_typifications", column: "typification_id"
  add_foreign_key "jabvox_audio_code_mappings", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_filename_patterns", "accounts"
  add_foreign_key "jabvox_audio_filename_patterns", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_infaltables", "accounts"
  add_foreign_key "jabvox_audio_infaltables", "jabvox_typifications", column: "typification_id"
  add_foreign_key "jabvox_audio_infaltables", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_jobs", "accounts"
  add_foreign_key "jabvox_audio_jobs", "jabvox_audio_pipelines", column: "pipeline_id"
  add_foreign_key "jabvox_audio_jobs", "jabvox_audio_storages", column: "storage_id"
  add_foreign_key "jabvox_audio_jobs", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_permissions", "accounts"
  add_foreign_key "jabvox_audio_permissions", "users"
  add_foreign_key "jabvox_audio_pipelines", "accounts"
  add_foreign_key "jabvox_audio_pipelines", "jabvox_ai_chat_models", column: "transcription_model_id"
  add_foreign_key "jabvox_audio_pipelines", "jabvox_typifications", column: "typification_id"
  add_foreign_key "jabvox_audio_pipelines", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_results", "accounts"
  add_foreign_key "jabvox_audio_results", "jabvox_audio_advisors", column: "advisor_id"
  add_foreign_key "jabvox_audio_results", "jabvox_audio_jobs", column: "job_id"
  add_foreign_key "jabvox_audio_results", "jabvox_typifications", column: "detected_typification_id"
  add_foreign_key "jabvox_audio_results", "jabvox_typifications", column: "typification_id"
  add_foreign_key "jabvox_audio_results", "users", column: "assigned_agent_id"
  add_foreign_key "jabvox_audio_results", "users", column: "created_by_id"
  add_foreign_key "jabvox_audio_stages", "jabvox_ai_chat_models", column: "llm_model_id"
  add_foreign_key "jabvox_audio_stages", "jabvox_audio_pipelines", column: "pipeline_id"
  add_foreign_key "jabvox_audio_storages", "accounts"
  add_foreign_key "jabvox_branch_hours", "jabvox_branches", column: "branch_id"
  add_foreign_key "jabvox_branch_managers", "jabvox_branches", column: "branch_id"
  add_foreign_key "jabvox_branch_managers", "users"
  add_foreign_key "jabvox_branches", "accounts"
  add_foreign_key "jabvox_branches", "users", column: "created_by_id"
  add_foreign_key "jabvox_bulk_whatsapp_batches", "accounts"
  add_foreign_key "jabvox_bulk_whatsapp_batches", "inboxes"
  add_foreign_key "jabvox_bulk_whatsapp_batches", "users", column: "created_by_id"
  add_foreign_key "jabvox_bulk_whatsapp_batches", "users", column: "sender_user_id"
  add_foreign_key "jabvox_bulk_whatsapp_configs", "accounts"
  add_foreign_key "jabvox_bulk_whatsapp_configs", "users", column: "created_by_id"
  add_foreign_key "jabvox_calendar_event_participants", "jabvox_calendar_events"
  add_foreign_key "jabvox_calendar_event_participants", "jabvox_calendar_external_people"
  add_foreign_key "jabvox_calendar_event_participants", "users"
  add_foreign_key "jabvox_calendar_event_reminders", "jabvox_calendar_events"
  add_foreign_key "jabvox_calendar_events", "accounts"
  add_foreign_key "jabvox_calendar_events", "contacts", name: "fk_jabvox_calendar_events_contact"
  add_foreign_key "jabvox_calendar_events", "jabvox_branches", column: "branch_id"
  add_foreign_key "jabvox_calendar_events", "jabvox_tasks"
  add_foreign_key "jabvox_calendar_events", "users"
  add_foreign_key "jabvox_calendar_events", "users", column: "created_by_id"
  add_foreign_key "jabvox_calendar_external_people", "accounts"
  add_foreign_key "jabvox_calendar_external_people", "users", column: "created_by_id"
  add_foreign_key "jabvox_call_logs", "accounts"
  add_foreign_key "jabvox_call_logs", "contacts"
  add_foreign_key "jabvox_call_logs", "conversations"
  add_foreign_key "jabvox_call_logs", "jabvox_typifications", column: "typification_id"
  add_foreign_key "jabvox_call_logs", "users"
  add_foreign_key "jabvox_campaigns", "accounts"
  add_foreign_key "jabvox_campaigns", "users", column: "created_by_id"
  add_foreign_key "jabvox_cdr_call_analyses", "accounts"
  add_foreign_key "jabvox_cdr_call_analyses", "jabvox_cdr_pipelines", column: "pipeline_id"
  add_foreign_key "jabvox_cdr_call_analyses", "users", column: "created_by_id"
  add_foreign_key "jabvox_cdr_configs", "accounts"
  add_foreign_key "jabvox_cdr_configs", "jabvox_cdr_pipelines", column: "default_pipeline_id"
  add_foreign_key "jabvox_cdr_extension_mappings", "accounts"
  add_foreign_key "jabvox_cdr_extension_mappings", "users"
  add_foreign_key "jabvox_cdr_pipelines", "accounts"
  add_foreign_key "jabvox_cdr_pipelines", "jabvox_ai_chat_models", column: "transcription_model_id"
  add_foreign_key "jabvox_cdr_pipelines", "jabvox_typifications", column: "typification_id"
  add_foreign_key "jabvox_cdr_pipelines", "users", column: "created_by_id"
  add_foreign_key "jabvox_cdr_records", "accounts"
  add_foreign_key "jabvox_cdr_report_permissions", "accounts"
  add_foreign_key "jabvox_cdr_report_permissions", "users"
  add_foreign_key "jabvox_cdr_stages", "jabvox_ai_chat_models", column: "llm_model_id"
  add_foreign_key "jabvox_cdr_stages", "jabvox_cdr_pipelines", column: "pipeline_id"
  add_foreign_key "jabvox_cdr_sync_runs", "accounts"
  add_foreign_key "jabvox_context_forge_handoffs", "accounts"
  add_foreign_key "jabvox_currencies", "accounts"
  add_foreign_key "jabvox_currencies", "users", column: "created_by_id"
  add_foreign_key "jabvox_custom_columns", "jabvox_custom_tables"
  add_foreign_key "jabvox_custom_table_rows", "contacts", on_delete: :cascade
  add_foreign_key "jabvox_custom_table_rows", "jabvox_custom_tables"
  add_foreign_key "jabvox_custom_tables", "accounts"
  add_foreign_key "jabvox_custom_tables", "users", column: "created_by_id"
  add_foreign_key "jabvox_dialer_accesses", "accounts", on_delete: :cascade
  add_foreign_key "jabvox_dialer_accesses", "users", on_delete: :cascade
  add_foreign_key "jabvox_dialer_call_logs", "accounts"
  add_foreign_key "jabvox_dialer_call_logs", "jabvox_dialer_campaign_contacts"
  add_foreign_key "jabvox_dialer_call_logs", "jabvox_dialer_campaigns"
  add_foreign_key "jabvox_dialer_call_logs", "jabvox_typifications", column: "typification_id"
  add_foreign_key "jabvox_dialer_call_logs", "users", column: "agent_id_jabvox", on_delete: :nullify
  add_foreign_key "jabvox_dialer_campaign_contacts", "accounts"
  add_foreign_key "jabvox_dialer_campaign_contacts", "contacts", on_delete: :nullify
  add_foreign_key "jabvox_dialer_campaign_contacts", "jabvox_dialer_campaigns"
  add_foreign_key "jabvox_dialer_campaign_contacts", "users", column: "created_by_id"
  add_foreign_key "jabvox_dialer_campaigns", "accounts"
  add_foreign_key "jabvox_dialer_campaigns", "jabvox_campaigns", on_delete: :nullify
  add_foreign_key "jabvox_dialer_campaigns", "users", column: "created_by_id"
  add_foreign_key "jabvox_dialer_state_logs", "accounts"
  add_foreign_key "jabvox_dialer_state_logs", "users", on_delete: :cascade
  add_foreign_key "jabvox_dialer_states", "accounts", on_delete: :cascade
  add_foreign_key "jabvox_dialer_states", "users", column: "created_by_id"
  add_foreign_key "jabvox_discounts", "accounts"
  add_foreign_key "jabvox_discounts", "users", column: "created_by_id"
  add_foreign_key "jabvox_email_send_logs", "accounts"
  add_foreign_key "jabvox_email_send_logs", "users"
  add_foreign_key "jabvox_email_templates", "accounts"
  add_foreign_key "jabvox_email_templates", "users", column: "created_by_id"
  add_foreign_key "jabvox_export_sync_logs", "accounts"
  add_foreign_key "jabvox_export_sync_logs", "jabvox_export_targets"
  add_foreign_key "jabvox_export_targets", "accounts"
  add_foreign_key "jabvox_export_targets", "users", column: "created_by_id"
  add_foreign_key "jabvox_field_visibilities", "accounts"
  add_foreign_key "jabvox_field_visibilities", "users"
  add_foreign_key "jabvox_flow_account_variables", "accounts"
  add_foreign_key "jabvox_flow_folders", "accounts"
  add_foreign_key "jabvox_flow_run_steps", "jabvox_flow_runs", column: "flow_run_id"
  add_foreign_key "jabvox_flow_runs", "accounts"
  add_foreign_key "jabvox_flow_runs", "jabvox_flow_versions", column: "version_id"
  add_foreign_key "jabvox_flow_runs", "jabvox_flows", column: "flow_id"
  add_foreign_key "jabvox_flow_runs", "users", column: "triggered_by", on_delete: :nullify
  add_foreign_key "jabvox_flow_versions", "jabvox_flows", column: "flow_id"
  add_foreign_key "jabvox_flow_versions", "users", column: "created_by", on_delete: :nullify
  add_foreign_key "jabvox_flows", "accounts"
  add_foreign_key "jabvox_flows", "jabvox_flow_folders", column: "folder_id", on_delete: :nullify
  add_foreign_key "jabvox_flows", "jabvox_flow_versions", column: "current_version_id", on_delete: :nullify
  add_foreign_key "jabvox_form_configs", "accounts"
  add_foreign_key "jabvox_form_submissions", "accounts"
  add_foreign_key "jabvox_form_submissions", "jabvox_forms"
  add_foreign_key "jabvox_form_submissions", "users", column: "created_by_id"
  add_foreign_key "jabvox_forms", "accounts"
  add_foreign_key "jabvox_forms", "users", column: "created_by_id"
  add_foreign_key "jabvox_hermes_action_logs", "accounts"
  add_foreign_key "jabvox_hermes_action_logs", "users"
  add_foreign_key "jabvox_hermes_agent_connections", "jabvox_hermes_agents", column: "hermes_agent_id"
  add_foreign_key "jabvox_hermes_agent_connections", "jabvox_hermes_connections", column: "hermes_connection_id"
  add_foreign_key "jabvox_hermes_agents", "accounts"
  add_foreign_key "jabvox_hermes_agents", "users"
  add_foreign_key "jabvox_hermes_connections", "accounts"
  add_foreign_key "jabvox_hermes_identities", "accounts"
  add_foreign_key "jabvox_hermes_provisioner_links", "accounts"
  add_foreign_key "jabvox_hermes_provisioner_links", "jabvox_hermes_provisioners", column: "hermes_provisioner_id"
  add_foreign_key "jabvox_hermes_sessions", "accounts"
  add_foreign_key "jabvox_hermes_sessions", "users"
  add_foreign_key "jabvox_hermes_user_permissions", "accounts"
  add_foreign_key "jabvox_hermes_user_permissions", "users"
  add_foreign_key "jabvox_integration_configs", "accounts"
  add_foreign_key "jabvox_internal_chat_members", "jabvox_internal_chats", column: "chat_id"
  add_foreign_key "jabvox_internal_chat_members", "users"
  add_foreign_key "jabvox_internal_chats", "accounts"
  add_foreign_key "jabvox_internal_chats", "users", column: "created_by_id"
  add_foreign_key "jabvox_internal_messages", "jabvox_internal_chats", column: "chat_id"
  add_foreign_key "jabvox_internal_messages", "users", column: "sender_id"
  add_foreign_key "jabvox_ip_whitelists", "accounts"
  add_foreign_key "jabvox_ip_whitelists", "users", column: "created_by_id"
  add_foreign_key "jabvox_item_types", "accounts"
  add_foreign_key "jabvox_item_types", "users", column: "created_by_id"
  add_foreign_key "jabvox_kanban_conversation_stages", "accounts"
  add_foreign_key "jabvox_kanban_conversation_stages", "conversations"
  add_foreign_key "jabvox_kanban_conversation_stages", "jabvox_kanban_funnels"
  add_foreign_key "jabvox_kanban_conversation_stages", "jabvox_kanban_stages"
  add_foreign_key "jabvox_kanban_conversation_stages", "users", column: "created_by_id"
  add_foreign_key "jabvox_kanban_funnel_affiliates", "jabvox_affiliates"
  add_foreign_key "jabvox_kanban_funnel_affiliates", "jabvox_kanban_funnels"
  add_foreign_key "jabvox_kanban_funnel_campaigns", "jabvox_campaigns"
  add_foreign_key "jabvox_kanban_funnel_campaigns", "jabvox_kanban_funnels"
  add_foreign_key "jabvox_kanban_funnel_inboxes", "inboxes"
  add_foreign_key "jabvox_kanban_funnel_inboxes", "jabvox_kanban_funnels"
  add_foreign_key "jabvox_kanban_funnels", "accounts"
  add_foreign_key "jabvox_kanban_funnels", "users", column: "created_by_id"
  add_foreign_key "jabvox_kanban_stage_automations", "accounts"
  add_foreign_key "jabvox_kanban_stage_automations", "inboxes"
  add_foreign_key "jabvox_kanban_stage_automations", "jabvox_email_templates"
  add_foreign_key "jabvox_kanban_stage_automations", "jabvox_kanban_stages"
  add_foreign_key "jabvox_kanban_stage_automations", "jabvox_kanban_stages", column: "target_stage_id", name: "fk_jabvox_stage_automations_target_stage"
  add_foreign_key "jabvox_kanban_stage_automations", "jabvox_sms_providers"
  add_foreign_key "jabvox_kanban_stage_automations", "users", column: "created_by_id"
  add_foreign_key "jabvox_kanban_stages", "accounts"
  add_foreign_key "jabvox_kanban_stages", "jabvox_kanban_funnels"
  add_foreign_key "jabvox_kanban_stages", "jabvox_kanban_stages", column: "auto_advance_target_stage_id", name: "fk_jabvox_kanban_stages_auto_advance_target"
  add_foreign_key "jabvox_kanban_stages", "users", column: "created_by_id"
  add_foreign_key "jabvox_lead_source_records", "accounts"
  add_foreign_key "jabvox_lead_source_records", "jabvox_lead_sources", column: "lead_source_id"
  add_foreign_key "jabvox_lead_sources", "accounts"
  add_foreign_key "jabvox_lead_sources", "users", column: "created_by_id"
  add_foreign_key "jabvox_management_answers", "accounts"
  add_foreign_key "jabvox_management_answers", "jabvox_management_questions", on_delete: :nullify
  add_foreign_key "jabvox_management_answers", "jabvox_management_states"
  add_foreign_key "jabvox_management_answers", "messages"
  add_foreign_key "jabvox_management_answers", "notes"
  add_foreign_key "jabvox_management_answers", "users", column: "created_by_id"
  add_foreign_key "jabvox_management_questions", "accounts"
  add_foreign_key "jabvox_management_questions", "jabvox_management_states"
  add_foreign_key "jabvox_management_questions", "users", column: "created_by_id"
  add_foreign_key "jabvox_management_states", "accounts"
  add_foreign_key "jabvox_management_states", "users", column: "created_by_id"
  add_foreign_key "jabvox_order_items", "jabvox_orders"
  add_foreign_key "jabvox_order_status_configs", "accounts"
  add_foreign_key "jabvox_order_status_configs", "users", column: "created_by_id"
  add_foreign_key "jabvox_orders", "accounts"
  add_foreign_key "jabvox_orders", "users", column: "created_by_id"
  add_foreign_key "jabvox_products", "accounts"
  add_foreign_key "jabvox_products", "jabvox_currencies"
  add_foreign_key "jabvox_products", "jabvox_item_types"
  add_foreign_key "jabvox_products", "jabvox_units_of_measure", column: "jabvox_unit_of_measure_id"
  add_foreign_key "jabvox_products", "users", column: "created_by_id"
  add_foreign_key "jabvox_provisioner_sessions", "jabvox_provisioner_api_tokens", column: "provisioner_api_token_id"
  add_foreign_key "jabvox_provisioning_chat_messages", "accounts"
  add_foreign_key "jabvox_provisioning_chat_messages", "users"
  add_foreign_key "jabvox_provisioning_transactions", "accounts"
  add_foreign_key "jabvox_provisioning_transactions", "jabvox_plans"
  add_foreign_key "jabvox_quick_buttons", "accounts"
  add_foreign_key "jabvox_quick_buttons", "users", column: "created_by_id"
  add_foreign_key "jabvox_response_bot_configs", "accounts"
  add_foreign_key "jabvox_response_bot_configs", "inboxes"
  add_foreign_key "jabvox_response_bot_configs", "jabvox_ai_chat_models"
  add_foreign_key "jabvox_response_bot_configs", "jabvox_ai_chat_models", column: "jabvox_audio_model_id"
  add_foreign_key "jabvox_response_bot_configs", "jabvox_ai_chat_models", column: "jabvox_image_model_id"
  add_foreign_key "jabvox_response_bot_configs", "jabvox_response_bot_roles"
  add_foreign_key "jabvox_response_bot_configs", "jabvox_response_bot_seats"
  add_foreign_key "jabvox_response_bot_documents", "accounts"
  add_foreign_key "jabvox_response_bot_documents", "users", column: "created_by_id"
  add_foreign_key "jabvox_saldo_configs", "accounts"
  add_foreign_key "jabvox_sales_report_accesses", "accounts"
  add_foreign_key "jabvox_sales_report_accesses", "users"
  add_foreign_key "jabvox_sms_campaigns", "accounts"
  add_foreign_key "jabvox_sms_campaigns", "jabvox_campaigns", on_delete: :nullify, validate: false
  add_foreign_key "jabvox_sms_campaigns", "jabvox_sms_providers"
  add_foreign_key "jabvox_sms_campaigns", "users", column: "created_by_id"
  add_foreign_key "jabvox_sms_messages", "accounts"
  add_foreign_key "jabvox_sms_messages", "contacts"
  add_foreign_key "jabvox_sms_messages", "jabvox_sms_campaigns"
  add_foreign_key "jabvox_sms_messages", "jabvox_sms_providers"
  add_foreign_key "jabvox_sms_messages", "users", column: "created_by_id"
  add_foreign_key "jabvox_sms_providers", "accounts"
  add_foreign_key "jabvox_smtp_configs", "accounts"
  add_foreign_key "jabvox_softphone_call_events", "accounts"
  add_foreign_key "jabvox_softphone_call_events", "jabvox_softphone_call_logs"
  add_foreign_key "jabvox_softphone_call_logs", "accounts"
  add_foreign_key "jabvox_softphone_call_logs", "users"
  add_foreign_key "jabvox_softphone_configs", "accounts"
  add_foreign_key "jabvox_softphone_extensions", "accounts"
  add_foreign_key "jabvox_softphone_extensions", "users"
  add_foreign_key "jabvox_task_activities", "accounts"
  add_foreign_key "jabvox_task_activities", "jabvox_tasks", column: "task_id"
  add_foreign_key "jabvox_task_activities", "users"
  add_foreign_key "jabvox_task_assignee_board_targets", "accounts"
  add_foreign_key "jabvox_task_assignee_board_targets", "jabvox_task_boards", column: "source_board_id"
  add_foreign_key "jabvox_task_assignee_board_targets", "jabvox_task_boards", column: "target_board_id"
  add_foreign_key "jabvox_task_assignee_board_targets", "users", column: "owner_id"
  add_foreign_key "jabvox_task_assignees", "accounts"
  add_foreign_key "jabvox_task_assignees", "jabvox_tasks", column: "task_id"
  add_foreign_key "jabvox_task_assignees", "users"
  add_foreign_key "jabvox_task_automation_runs", "accounts"
  add_foreign_key "jabvox_task_automation_runs", "jabvox_task_automations", column: "automation_id"
  add_foreign_key "jabvox_task_automation_runs", "jabvox_tasks", column: "task_id"
  add_foreign_key "jabvox_task_automation_runs", "users", column: "created_by_id"
  add_foreign_key "jabvox_task_automations", "accounts"
  add_foreign_key "jabvox_task_automations", "inboxes"
  add_foreign_key "jabvox_task_automations", "jabvox_email_templates", column: "email_template_id"
  add_foreign_key "jabvox_task_automations", "jabvox_sms_providers", column: "sms_provider_id"
  add_foreign_key "jabvox_task_automations", "jabvox_tasks", column: "task_id"
  add_foreign_key "jabvox_task_automations", "users", column: "created_by_id"
  add_foreign_key "jabvox_task_boards", "accounts"
  add_foreign_key "jabvox_task_boards", "users", column: "created_by_id"
  add_foreign_key "jabvox_task_boards", "users", column: "owner_id"
  add_foreign_key "jabvox_task_stage_automations", "accounts"
  add_foreign_key "jabvox_task_stage_automations", "inboxes"
  add_foreign_key "jabvox_task_stage_automations", "jabvox_email_templates", column: "email_template_id"
  add_foreign_key "jabvox_task_stage_automations", "jabvox_sms_providers", column: "sms_provider_id"
  add_foreign_key "jabvox_task_stage_automations", "jabvox_task_stages", column: "stage_id"
  add_foreign_key "jabvox_task_stage_automations", "jabvox_task_stages", column: "target_stage_id"
  add_foreign_key "jabvox_task_stages", "accounts"
  add_foreign_key "jabvox_task_stages", "jabvox_task_boards", column: "board_id"
  add_foreign_key "jabvox_task_stages", "users", column: "created_by_id"
  add_foreign_key "jabvox_task_webhook_deliveries", "accounts"
  add_foreign_key "jabvox_task_webhook_deliveries", "jabvox_task_stage_automations", column: "automation_id"
  add_foreign_key "jabvox_task_webhook_deliveries", "jabvox_tasks", column: "task_id"
  add_foreign_key "jabvox_task_webhook_deliveries", "users", column: "created_by_id"
  add_foreign_key "jabvox_tasks", "accounts"
  add_foreign_key "jabvox_tasks", "jabvox_task_boards", column: "board_id"
  add_foreign_key "jabvox_tasks", "jabvox_task_stages", column: "stage_id"
  add_foreign_key "jabvox_tasks", "jabvox_tasks", column: "recurrence_parent_id", on_delete: :nullify
  add_foreign_key "jabvox_tasks", "jabvox_tasks", column: "source_task_id", on_delete: :nullify
  add_foreign_key "jabvox_tasks", "users", column: "assignee_id"
  add_foreign_key "jabvox_tasks", "users", column: "created_by_id"
  add_foreign_key "jabvox_tax_rates", "accounts"
  add_foreign_key "jabvox_tax_rates", "users", column: "created_by_id"
  add_foreign_key "jabvox_typifications", "accounts"
  add_foreign_key "jabvox_typifications", "users", column: "created_by_id"
  add_foreign_key "jabvox_units_of_measure", "accounts"
  add_foreign_key "jabvox_units_of_measure", "users", column: "created_by_id"
  add_foreign_key "jabvox_user_extensions", "accounts"
  add_foreign_key "jabvox_user_extensions", "users"
  add_foreign_key "jabvox_voip_configs", "accounts"
  add_foreign_key "jabvox_whatsapp_flow_answers", "jabvox_whatsapp_flow_submissions"
  add_foreign_key "jabvox_whatsapp_flow_submissions", "accounts"
  add_foreign_key "jabvox_whatsapp_flow_submissions", "contacts"
  add_foreign_key "jabvox_whatsapp_flow_submissions", "conversations"
  add_foreign_key "jabvox_whatsapp_flow_submissions", "jabvox_whatsapp_flows"
  add_foreign_key "jabvox_whatsapp_flow_submissions", "messages"
  add_foreign_key "jabvox_whatsapp_flow_versions", "jabvox_whatsapp_flows"
  add_foreign_key "jabvox_whatsapp_flow_versions", "users", column: "created_by_id"
  add_foreign_key "jabvox_whatsapp_flows", "accounts"
  add_foreign_key "jabvox_whatsapp_flows", "inboxes"
  add_foreign_key "jabvox_whatsapp_flows", "users", column: "created_by_id"
  add_foreign_key "jabvox_whatsapp_template_logs", "accounts"
  add_foreign_key "jabvox_whatsapp_template_logs", "jabvox_whatsapp_templates"
  add_foreign_key "jabvox_whatsapp_template_logs", "users"
  add_foreign_key "jabvox_whatsapp_template_permissions", "accounts"
  add_foreign_key "jabvox_whatsapp_template_permissions", "users"
  add_foreign_key "jabvox_whatsapp_template_versions", "jabvox_whatsapp_templates"
  add_foreign_key "jabvox_whatsapp_template_versions", "users", column: "created_by_id"
  add_foreign_key "jabvox_whatsapp_templates", "accounts"
  add_foreign_key "jabvox_whatsapp_templates", "inboxes", on_delete: :cascade
  add_foreign_key "jabvox_whatsapp_templates", "jabvox_whatsapp_flows"
  add_foreign_key "jabvox_whatsapp_templates", "users", column: "created_by_id"
  add_foreign_key "user_sessions", "users"
  create_trigger("accounts_after_insert_row_tr", :generated => true, :compatibility => 1).
      on("accounts").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  create_trigger("conversations_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("conversations").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('conv_dpid_seq_' || NEW.account_id);"
  end

  create_trigger("camp_dpid_before_insert", :generated => true, :compatibility => 1).
      on("accounts").
      name("camp_dpid_before_insert").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  create_trigger("campaigns_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("campaigns").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end

end
