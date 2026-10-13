# frozen_string_literal: true

module NotificationModuleNotifications
  extend ActiveSupport::Concern

  TYPES = %w[
    jabvox_task_reminder
    jabvox_internal_chat_message
    jabvox_task_assigned
    jabvox_calendar_event_reminder
    jabvox_kanban_stage_changed
    jabvox_lead_import_finished
    jabvox_bulk_whatsapp_finished
    jabvox_whatsapp_template_status
    jabvox_ai_balance_movement
    jabvox_ai_provisioning_approval
  ].freeze

  def module_notification?
    TYPES.include?(notification_type)
  end

  def module_notification_title
    stored_title = meta&.dig('title').to_s
    return stored_title if stored_title.present?
    return I18n.t('notifications.task_reminder_title', default: 'Task reminder') if jabvox_task_reminder?

    notification_type.humanize
  end

  def module_notification_body
    stored_body = meta&.dig('body').to_s
    return stored_body if stored_body.present?
    return primary_actor.title_jabvox.to_s if jabvox_task_reminder? && primary_actor.respond_to?(:title_jabvox)

    ''
  end
end
