# Handles WhatsApp Groups API webhook events, layered onto the base
# Webhooks::WhatsappEventsJob (prepended in 99_jabvox_extensions). Two kinds of
# group traffic reach us:
#
#   1. Metadata events (field: group_participants_update / group_settings_update /
#      group_status_update / group_lifecycle_update) → member joins/leaves, name,
#      status. Applied by IncomingGroupEventService (no conversation touched).
#
#   2. Content messages (field: "messages") that carry a `group_id` inside
#      value.messages[]. Meta delivers these on the SAME field as 1:1 messages,
#      so without this interception Chatwoot would open a 1:1 conversation for the
#      individual sender. We route them to IncomingGroupMessageService, which
#      creates/updates ONE conversation per group and shows who wrote each message.
#
# Everything else (1:1 messages, echoes, calls, statuses) falls through to `super`.
module Jabvox::WhatsappGroupEventsJob
  GROUP_FIELDS = %w[
    group_lifecycle_update group_participants_update
    group_settings_update group_status_update
  ].freeze

  def handle_message_events(channel, params)
    return handle_group_event(channel, params) if group_event?(params)
    return handle_group_message(channel, params) if group_message?(params)

    super
  end

  private

  # Skip the parent's per-sender mutex for group traffic. Metadata events have no
  # sender; group content messages lock per group id inside their own service, so a
  # per-participant lock here would be wrong (many senders, one conversation).
  def contact_sender_id(params)
    return nil if group_event?(params) || group_message?(params)

    super
  end

  def group_event?(params)
    GROUP_FIELDS.include?(params.dig(:entry, 0, :changes, 0, :field))
  end

  # A regular "messages" webhook whose first message carries a group_id is a message
  # sent INSIDE a group, not a 1:1 message.
  def group_message?(params)
    return false unless params.dig(:entry, 0, :changes, 0, :field) == 'messages'

    value = params.dig(:entry, 0, :changes, 0, :value) || {}
    group_id_from_value(value).present?
  end

  def group_id_from_value(value)
    value.dig(:messages, 0, :group_id) || value[:group_id]
  end

  def handle_group_event(channel, params)
    field = params.dig(:entry, 0, :changes, 0, :field)
    value = params.dig(:entry, 0, :changes, 0, :value) || {}
    Jabvox::Whatsapp::IncomingGroupEventService.new(channel: channel, field: field, value: value).perform
  rescue StandardError => e
    Rails.logger.error("[Jabvox WhatsApp group event] #{field} #{e.class}: #{e.message}")
  end

  def handle_group_message(channel, params)
    value = params.dig(:entry, 0, :changes, 0, :value) || {}
    Jabvox::Whatsapp::IncomingGroupMessageService.new(
      channel: channel, group_id: group_id_from_value(value), value: value
    ).perform
  rescue StandardError => e
    Rails.logger.error("[Jabvox WhatsApp group message] #{e.class}: #{e.message}")
  end
end
