# Normalizes one row of "a WhatsApp template was sent" for Informes → Plantillas,
# regardless of where the send came from: a bulk batch (JabvoxBulkWhatsappRecipient)
# or an agent sending a template 1-a-1 from a conversation (a plain Message with
# additional_attributes.template_params — see Messages::MessageBuilder). Both ends
# up exposing the exact interface Jabvox::BulkWhatsappReplyStatus/DeliveryStatus
# already operate on (id, conversation_id, sent_at_jabvox, chatwoot_message_id,
# name_jabvox, phone_number_jabvox, template_name_jabvox, status_jabvox,
# error_code_jabvox, error_message_jabvox), so both sources reuse that pipeline
# unchanged instead of forking it.
module Jabvox::TemplateSendRow
  # id is namespaced per source so a bulk recipient #7 and an individual message
  # #7 (different tables, both starting their own id sequence) never collide as
  # the same key in first_reply_map's { recipient.id => Reply } result hash.
  Row = Struct.new(
    :id, :conversation_id, :sent_at_jabvox, :chatwoot_message_id,
    :name_jabvox, :phone_number_jabvox, :template_name_jabvox, :status_jabvox,
    :error_code_jabvox, :error_message_jabvox, :source
  )

  def self.from_bulk_recipient(recipient)
    Row.new(
      "bulk-#{recipient.id}", recipient.conversation_id, recipient.sent_at_jabvox, recipient.chatwoot_message_id,
      recipient.name_jabvox, recipient.phone_number_jabvox, recipient.template_name_jabvox, recipient.status_jabvox,
      recipient.error_code_jabvox, recipient.error_message_jabvox, 'bulk'
    )
  end

  # message.status is sent/delivered/read/failed (delivered/read already implies
  # sent successfully) — collapsed to sent/failed here because delivered/read are
  # resolved separately, from MessageStatusEvent, same as the bulk recipient path.
  def self.from_message(message, contact_name:, contact_phone:)
    Row.new(
      "msg-#{message.id}", message.conversation_id, message.created_at, message.id,
      contact_name, contact_phone, message.additional_attributes.dig('template_params', 'name'),
      message.status == 'failed' ? 'failed' : 'sent',
      nil, message.content_attributes['external_error'], 'individual'
    )
  end
end
