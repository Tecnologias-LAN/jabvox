# frozen_string_literal: true

# Persists module events in the existing account/user notification stream. Recipients
# are selected by each event producer; this service enforces account and module scope.
class Jabvox::ModuleNotificationService
  EVENT_FEATURES = {
    jabvox_internal_chat_message: 'jabvox_internal_chat',
    jabvox_task_assigned: 'jabvox_tasks',
    jabvox_task_reminder: 'jabvox_tasks',
    jabvox_calendar_event_reminder: 'jabvox_calendar',
    jabvox_kanban_stage_changed: 'jabvox_kanban',
    jabvox_lead_import_finished: 'jabvox_lead_import',
    jabvox_bulk_whatsapp_finished: 'jabvox_bulk_whatsapp',
    jabvox_whatsapp_template_status: 'jabvox_whatsapp_templates',
    jabvox_ai_balance_movement: 'jabvox_ai_chat',
    jabvox_ai_provisioning_approval: 'jabvox_ai_chat_provisioning'
  }.freeze

  ADMIN_ONLY_TYPES = %i[jabvox_ai_balance_movement].freeze

  def self.feature_for(type)
    EVENT_FEATURES[type.to_sym]
  end

  # rubocop:disable Metrics/ParameterLists
  def self.create!(account:, user:, type:, actor:, title:, body:, path:, secondary_actor: nil)
    feature = feature_for(type)
    raise ArgumentError, "Unsupported Jabvox notification type: #{type}" unless feature
    return unless eligible_recipient?(account, user, actor, type, feature)

    attributes = {
      notification_type: type,
      secondary_actor: secondary_actor,
      read_at: nil,
      snoozed_until: nil,
      last_activity_at: Time.current,
      meta: { module: feature, title: title, body: body, path: path }
    }
    persist_notification!(account, user, actor, attributes)
  end
  # rubocop:enable Metrics/ParameterLists

  def self.eligible_recipient?(account, user, actor, type, feature)
    return false unless user && account.feature_enabled?(feature) && actor_account_id(actor) == account.id

    account_user = account.account_users.find_by(user_id: user.id)
    account_user && (ADMIN_ONLY_TYPES.exclude?(type.to_sym) || account_user.administrator?)
  end
  private_class_method :eligible_recipient?

  def self.persist_notification!(account, user, actor, attributes)
    notification = Notification.find_or_initialize_by(
      account: account,
      user: user,
      primary_actor: actor
    )
    notification.assign_attributes(attributes)
    notification.save!
    notification
  rescue ActiveRecord::RecordNotUnique
    notification = Notification.find_by(account: account, user: user, primary_actor: actor)
    raise unless notification

    notification.update!(attributes)
    notification
  end
  private_class_method :persist_notification!

  def self.actor_account_id(actor)
    actor.try(:account_id) || actor.try(:account)&.id
  end
  private_class_method :actor_account_id
end
