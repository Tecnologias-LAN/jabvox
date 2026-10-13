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

class CustomRole < ApplicationRecord
  belongs_to :account
  has_many :account_users, dependent: :nullify

  before_destroy :capture_filtered_unread_count_user_ids, prepend: true
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :filtered_unread_count_permissions_changed?
  after_destroy_commit :invalidate_filtered_unread_count_visibility_destroy

  # Chatwoot base permissions.
  BASE_PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    contact_manage
    report_manage
  ].freeze

  # Per-module Jabvox permissions, grouped by module. Each entry gates a real
  # action in that module's controllers/scoping (see JabvoxPermissions concern).
  # Naming: jabvox_<module>_<capability>.
  JABVOX_PERMISSIONS = %w[
    jabvox_contacts_view_all
    jabvox_contacts_assign
    jabvox_contacts_edit
    jabvox_contacts_delete
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
    jabvox_whatsapp_flows_manage
    jabvox_analytics_access
    jabvox_analytics_manage
    jabvox_lead_import_manage
    jabvox_data_export_manage
    jabvox_bulk_whatsapp_send
    jabvox_whatsapp_groups_manage
    jabvox_voice_broadcast_manage
    jabvox_custom_data_manage
    jabvox_dialer_use
    jabvox_dialer_manage
    jabvox_click_to_call_use
    jabvox_internal_chat_use
    jabvox_calendar_manage
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
    jabvox_flows_manage
    jabvox_ai_chat_provisioning_manage
  ].freeze

  PERMISSIONS = (BASE_PERMISSIONS + JABVOX_PERMISSIONS).freeze

  # Which account feature (module) must be enabled for each Jabvox permission to
  # be grantable. Permissions not listed (base permissions and modules without a
  # per-account toggle: integrations, ip_whitelist, typifications,
  # field_visibilities, campaigns, affiliates, app_states, reports, …) are always
  # grantable. Mirrors MODULE_FEATURE_FLAG in CustomRoleModal.vue.
  JABVOX_PERMISSION_FEATURES = {
    %w[jabvox_kanban_view_all jabvox_kanban_manage] => 'jabvox_kanban',
    %w[jabvox_tasks_view_all jabvox_tasks_manage] => 'jabvox_tasks',
    %w[jabvox_cdr_view_reports jabvox_cdr_manage] => 'jabvox_cdr',
    %w[jabvox_audio_access jabvox_audio_view_reports jabvox_audio_manage] => 'jabvox_audio_analysis',
    %w[jabvox_ai_chat_use jabvox_ai_chat_manage] => 'jabvox_ai_chat',
    %w[jabvox_whatsapp_templates_manage] => 'jabvox_whatsapp_templates',
    %w[jabvox_whatsapp_flows_manage] => 'jabvox_whatsapp_flows',
    %w[jabvox_analytics_access jabvox_analytics_manage] => 'jabvox_analytics',
    %w[jabvox_lead_import_manage] => 'jabvox_lead_import',
    %w[jabvox_data_export_manage] => 'jabvox_data_export',
    %w[jabvox_bulk_whatsapp_send] => 'jabvox_bulk_whatsapp',
    %w[jabvox_whatsapp_groups_manage] => 'jabvox_whatsapp_groups',
    %w[jabvox_voice_broadcast_manage] => 'jabvox_voice_broadcast',
    %w[jabvox_custom_data_manage] => 'jabvox_customization',
    %w[jabvox_dialer_use jabvox_dialer_manage] => 'jabvox_dialer',
    %w[jabvox_click_to_call_use] => 'jabvox_click_to_call',
    %w[jabvox_internal_chat_use] => 'jabvox_internal_chat',
    %w[jabvox_calendar_manage] => 'jabvox_calendar',
    %w[jabvox_forms_manage] => 'jabvox_forms',
    %w[jabvox_sms_view jabvox_sms_manage] => 'jabvox_sms',
    %w[jabvox_email_manage] => 'jabvox_email',
    %w[jabvox_saldo_manage] => 'jabvox_saldo',
    %w[jabvox_voip_manage] => 'jabvox_voip',
    %w[jabvox_products_manage jabvox_orders_manage] => 'jabvox_products',
    %w[jabvox_affiliates_manage] => 'jabvox_affiliates',
    %w[jabvox_flows_manage] => 'jabvox_advanced_automations',
    %w[jabvox_ai_chat_provisioning_manage] => 'jabvox_ai_chat_provisioning'
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

  def filtered_unread_count_permissions_changed?
    previous_changes.key?('permissions')
  end

  def capture_filtered_unread_count_user_ids
    @filtered_unread_count_user_ids = account_users.pluck(:user_id)
  end

  def invalidate_filtered_unread_count_visibility_update
    invalidate_filtered_unread_count_visibility(account_users.pluck(:user_id))
  end

  def invalidate_filtered_unread_count_visibility_destroy
    invalidate_filtered_unread_count_visibility(@filtered_unread_count_user_ids)
  end

  def invalidate_filtered_unread_count_visibility(user_ids)
    invalidator = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account)
    visibility_changed = invalidator.users_visibility_changed!(user_ids: user_ids)

    dispatch_account_cache_invalidated if visibility_changed
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end
