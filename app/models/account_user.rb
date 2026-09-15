# == Schema Information
#
# Table name: account_users
#
#  id                             :bigint           not null, primary key
#  active_at                      :datetime
#  auto_offline                   :boolean          default(TRUE), not null
#  availability                   :integer          default("online"), not null
#  jabvox_app_state_changed_at    :datetime
#  jabvox_dialer_state            :string           default("inactive")
#  jabvox_dialer_state_changed_at :datetime
#  role                           :integer          default("agent")
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :bigint
#  agent_capacity_policy_id       :bigint
#  custom_role_id                 :bigint
#  inviter_id                     :bigint
#  jabvox_app_state_id            :integer
#  user_id                        :bigint
#
# Indexes
#
#  index_account_users_on_account_id                (account_id)
#  index_account_users_on_agent_capacity_policy_id  (agent_capacity_policy_id)
#  index_account_users_on_custom_role_id            (custom_role_id)
#  index_account_users_on_user_id                   (user_id)
#  uniq_user_id_per_account_id                      (account_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_app_state_id => jabvox_app_states.id) ON DELETE => nullify
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true

  enum role: { agent: 0, administrator: 1 }
  enum availability: { online: 0, offline: 1, busy: 2 }

  accepts_nested_attributes_for :account

  after_create_commit :notify_creation, :create_notification_setting
  after_destroy :notify_deletion, :remove_user_from_account
  after_save :update_presence_in_redis, if: :saved_change_to_availability?
  after_commit :invalidate_filtered_unread_count_visibility, on: [:create, :destroy]
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :filtered_unread_count_visibility_changed?
  # Seguridad: JabvoxHermesUserPermission#permissions_for_role se deriva del rol en el
  # momento de sync_from_role!, y esa tabla NO se releía en cada request — quedaba
  # obsoleta si el rol/custom_role cambiaba después. Sin este callback, degradar a un
  # admin a un rol personalizado restrictivo dejaba su fila de permisos de Hermes con
  # los privilegios amplios de cuando era admin (read/create/write/execute/configure),
  # aunque el resto de la app ya lo tratara como agente restringido.
  after_update_commit :resync_hermes_permissions, if: :saved_change_to_role_or_custom_role?

  validates :user_id, uniqueness: { scope: :account_id }

  def create_notification_setting
    setting = user.notification_settings.new(account_id: account.id)
    setting.selected_email_flags = [:email_conversation_assignment]
    setting.selected_push_flags = [:push_conversation_assignment]
    setting.save!
  end

  def remove_user_from_account
    ::Agents::DestroyJob.perform_later(account, user)
  end

  def permissions
    administrator? ? ['administrator'] : ['agent']
  end

  def push_event_data
    {
      id: id,
      availability: availability,
      role: role,
      user_id: user_id
    }
  end

  private

  def notify_creation
    Rails.configuration.dispatcher.dispatch(AGENT_ADDED, Time.zone.now, account: account)
  end

  def notify_deletion
    Rails.configuration.dispatcher.dispatch(AGENT_REMOVED, Time.zone.now, account: account)
  end

  def update_presence_in_redis
    OnlineStatusTracker.set_status(account.id, user.id, availability)
  end

  def filtered_unread_count_visibility_changed?
    previous_changes.key?('role') || previous_changes.key?('custom_role_id')
  end

  def saved_change_to_role_or_custom_role?
    saved_change_to_role? || saved_change_to_custom_role_id?
  end

  def resync_hermes_permissions
    JabvoxHermesUserPermission.sync_from_role!(account_id, user_id)
  rescue StandardError => e
    # Best-effort: un fallo aquí no debe bloquear el cambio de rol en sí (que ya se
    # guardó). Se loguea para investigar, pero la fuente de verdad real en cada
    # request sigue siendo JabvoxPermissions/Authorizer, no esta tabla derivada.
    Rails.logger.error("[AccountUser#resync_hermes_permissions] account_id=#{account_id} user_id=#{user_id}: #{e.message}")
  end

  def invalidate_filtered_unread_count_visibility
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).user_visibility_changed!(user_id: user_id)
  end

  def invalidate_filtered_unread_count_visibility_update
    dispatch_account_cache_invalidated if invalidate_filtered_unread_count_visibility
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end

AccountUser.prepend_mod_with('AccountUser')
AccountUser.include_mod_with('Audit::AccountUser')
AccountUser.include_mod_with('Concerns::AccountUser')
