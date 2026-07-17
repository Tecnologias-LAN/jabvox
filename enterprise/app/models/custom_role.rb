# == Schema Information
#
# Table name: custom_roles
#
#  id          :bigint           not null, primary key
#  description :string
#  name        :string
#  permissions :text             default([]), is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_custom_roles_on_account_id  (account_id)
#
#

# Available permissions for custom roles:
# - 'conversation_manage': Can manage all conversations.
# - 'conversation_unassigned_manage': Can manage unassigned conversations and assign to self.
# - 'conversation_participating_manage': Can manage conversations they are participating in (assigned to or a participant).
# - 'contact_manage': Can manage contacts.
# - 'report_manage': Can manage reports.
# - 'knowledge_base_manage': Can manage knowledge base portals.

class CustomRole < ApplicationRecord
  belongs_to :account
  has_many :account_users, dependent: :nullify

  # Chatwoot base permissions.
  BASE_PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    contact_manage
    report_manage
    knowledge_base_manage
  ].freeze

  # Per-module Jabvox permissions, grouped by module. Each entry gates a real
  # action in that module's controllers/scoping (see JabvoxPermissions concern).
  # Naming: jabvox_<module>_<capability>.
  JABVOX_PERMISSIONS = %w[
    jabvox_leads_view_all
    jabvox_leads_assign
    jabvox_leads_edit
    jabvox_leads_delete
    jabvox_kanban_view_all
    jabvox_kanban_manage
    jabvox_tasks_view_all
    jabvox_tasks_manage
    jabvox_cdr_view_reports
    jabvox_cdr_manage
    jabvox_audio_access
    jabvox_audio_view_reports
    jabvox_audio_manage
    jabvox_ai_chat_use
    jabvox_ai_chat_manage
    jabvox_whatsapp_templates_manage
    jabvox_analytics_access
    jabvox_analytics_manage
    jabvox_lead_import_manage
    jabvox_data_export_manage
    jabvox_bulk_whatsapp_send
    jabvox_custom_data_manage
    jabvox_dialer_use
    jabvox_dialer_manage
    jabvox_click_to_call_use
    jabvox_internal_chat_use
    jabvox_calendar_manage
    jabvox_response_bot_manage
    jabvox_forms_manage
    jabvox_sms_view
    jabvox_sms_manage
    jabvox_email_manage
    jabvox_saldo_manage
    jabvox_voip_manage
    jabvox_integration_manage
    jabvox_ip_whitelist_manage
    jabvox_products_manage
    jabvox_orders_manage
    jabvox_typifications_manage
    jabvox_management_states_manage
    jabvox_field_visibilities_manage
    jabvox_sales_reports_manage
    jabvox_campaigns_manage
    jabvox_affiliates_manage
    jabvox_app_states_manage
    jabvox_reports_view
  ].freeze

  PERMISSIONS = (BASE_PERMISSIONS + JABVOX_PERMISSIONS).freeze

  # Which account feature (module) must be enabled for each Jabvox permission to
  # be grantable. Permissions not listed (base permissions and modules without a
  # per-account toggle: integrations, ip_whitelist, typifications,
  # field_visibilities, campaigns, affiliates, app_states, reports, …) are always
  # grantable. Mirrors MODULE_FEATURE_FLAG in CustomRoleModal.vue.
  JABVOX_PERMISSION_FEATURES = {
    %w[jabvox_leads_view_all jabvox_leads_assign jabvox_leads_edit jabvox_leads_delete] => 'jabvox_leads',
    %w[jabvox_kanban_view_all jabvox_kanban_manage] => 'jabvox_kanban',
    %w[jabvox_tasks_view_all jabvox_tasks_manage] => 'jabvox_tasks',
    %w[jabvox_cdr_view_reports jabvox_cdr_manage] => 'jabvox_cdr',
    %w[jabvox_audio_access jabvox_audio_view_reports jabvox_audio_manage] => 'jabvox_audio_analysis',
    %w[jabvox_ai_chat_use jabvox_ai_chat_manage] => 'jabvox_ai_chat',
    %w[jabvox_whatsapp_templates_manage] => 'jabvox_whatsapp_templates',
    %w[jabvox_analytics_access jabvox_analytics_manage] => 'jabvox_analytics',
    %w[jabvox_lead_import_manage] => 'jabvox_lead_import',
    %w[jabvox_data_export_manage] => 'jabvox_data_export',
    %w[jabvox_bulk_whatsapp_send] => 'jabvox_bulk_whatsapp',
    %w[jabvox_custom_data_manage] => 'jabvox_customization',
    %w[jabvox_dialer_use jabvox_dialer_manage] => 'jabvox_dialer',
    %w[jabvox_click_to_call_use] => 'jabvox_click_to_call',
    %w[jabvox_internal_chat_use] => 'jabvox_internal_chat',
    %w[jabvox_calendar_manage] => 'jabvox_calendar',
    %w[jabvox_response_bot_manage] => 'jabvox_response_bot',
    %w[jabvox_forms_manage] => 'jabvox_forms',
    %w[jabvox_sms_view jabvox_sms_manage] => 'jabvox_sms',
    %w[jabvox_email_manage] => 'jabvox_email',
    %w[jabvox_saldo_manage] => 'jabvox_saldo',
    %w[jabvox_voip_manage] => 'jabvox_voip',
    %w[jabvox_products_manage jabvox_orders_manage] => 'jabvox_products',
    %w[jabvox_affiliates_manage] => 'jabvox_affiliates'
  }.flat_map { |perms, feature| perms.map { |p| [p, feature] } }.to_h.freeze

  # Can `permission` be granted on `account` right now? False only when the
  # permission belongs to a module the account has disabled. Unknown feature
  # names (no account toggle defined) never block a permission.
  def self.permission_available?(account, permission)
    feature = JABVOX_PERMISSION_FEATURES[permission.to_s]
    return true if feature.nil?

    account.feature_enabled?(feature)
  rescue NoMethodError
    true
  end

  validates :name, presence: true
  validate :permissions_within_catalog

  # Convenience: does this role grant the given permission key?
  def grants?(permission)
    permissions.include?(permission.to_s)
  end

  private

  # Each entry must be a known permission (array-inclusion validates the whole
  # array, so we check element-by-element for clearer errors and correctness).
  def permissions_within_catalog
    invalid = Array(permissions) - PERMISSIONS
    return if invalid.empty?

    errors.add(:permissions, "contains unknown permissions: #{invalid.join(', ')}")
  end
end
