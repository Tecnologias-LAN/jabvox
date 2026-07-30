# Handles WhatsApp Groups API webhook events, layered onto the base
# Webhooks::WhatsappEventsJob (prepended in 99_jabvox_extensions). Meta delivers
# group events under four `field` values; each carries the group id and the
# change. Non-group payloads fall through to `super` (calls, messages, echoes).
module Jabvox::WhatsappGroupEventsJob
  GROUP_FIELDS = %w[
    group_lifecycle_update group_participants_update
    group_settings_update group_status_update
  ].freeze

  def handle_message_events(channel, params)
    return handle_group_event(channel, params) if group_event?(params)

    super
  end

  private

  # Skip the parent's per-sender mutex for group events (they lock per group id
  # inside the service instead).
  def contact_sender_id(params)
    return nil if group_event?(params)

    super
  end

  def group_event?(params)
    GROUP_FIELDS.include?(params.dig(:entry, 0, :changes, 0, :field))
  end

  def handle_group_event(channel, params)
    field = params.dig(:entry, 0, :changes, 0, :field)
    value = params.dig(:entry, 0, :changes, 0, :value) || {}
    Jabvox::Whatsapp::IncomingGroupEventService.new(channel: channel, field: field, value: value).perform
  rescue StandardError => e
    Rails.logger.error("[Jabvox WhatsApp group event] #{field} #{e.class}: #{e.message}")
  end
end
