# Reconciles bulk WhatsApp recipients with Meta's real delivery outcome.
#
# The n8n send POST usually returns 200 even when Meta later rejects the message
# (status flips to `failed` with an external_error). So besides the n8n callback,
# we watch Chatwoot's own message_updated event: when an outgoing message that a
# bulk recipient is tracking (by chatwoot_message_id) turns failed, we mirror the
# error onto the recipient and recompute its batch's status.
class JabvoxBulkWhatsappListener < BaseListener
  def message_updated(event)
    message, = extract_message_and_account(event)
    return unless message&.outgoing?

    recipient = JabvoxBulkWhatsappRecipient.find_by(chatwoot_message_id: message.id)
    return unless recipient

    reconcile(recipient, message)
  rescue StandardError => e
    Rails.logger.error("[BulkWhatsapp reconcile] message=#{event.data&.dig(:message)&.id} #{e.class}: #{e.message}")
  end

  private

  def reconcile(recipient, message)
    if message.status == 'failed'
      external_error = message.content_attributes&.dig('external_error')
      recipient.update!(
        status_jabvox: 'failed',
        error_code_jabvox: recipient.error_code_jabvox.presence || 'meta_failed',
        error_message_jabvox: external_error.presence || recipient.error_message_jabvox
      )
      recipient.batch.recalculate_status!
    elsif message.status == 'delivered' || message.status == 'sent' || message.status == 'read'
      # Meta confirmed delivery — make sure it isn't stuck as pending/failed.
      return if recipient.status_jabvox == 'sent'

      recipient.update!(status_jabvox: 'sent', sent_at_jabvox: recipient.sent_at_jabvox || Time.current,
                        error_code_jabvox: nil, error_message_jabvox: nil)
      recipient.batch.recalculate_status!
    end
  end
end
