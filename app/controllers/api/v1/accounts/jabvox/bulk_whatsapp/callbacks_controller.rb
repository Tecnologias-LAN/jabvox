# Callback n8n calls with the result of each bulk WhatsApp send. Not user-gated
# (n8n is external): it authenticates with the per-batch secret token and only
# ever reads a fixed, whitelisted set of fields — it never evaluates content,
# never mass-assigns, and never touches a row outside the authenticated batch.
class Api::V1::Accounts::Jabvox::BulkWhatsapp::CallbacksController < Api::V1::Accounts::BaseController
  ERROR_MSG_LIMIT = 500
  ERROR_CODE_LIMIT = 40

  skip_before_action :authenticate_user!, raise: false
  skip_before_action :check_authorization, raise: false
  before_action :set_batch_by_uuid
  before_action :verify_callback_token

  def results
    if recipient_params.present?
      update_recipient(recipient_params)
      @batch.recalculate_status!
    elsif summary_params.present?
      apply_summary(summary_params)
    end
    head :ok
  rescue StandardError => e
    Rails.logger.error("[BulkWhatsapp callback] batch=#{@batch&.id} #{e.class}: #{e.message}")
    head :unprocessable_entity
  end

  private

  def set_batch_by_uuid
    uuid = params[:batch_uuid].to_s
    @batch = Current.account.jabvox_bulk_whatsapp_batches.find_by(batch_uuid_jabvox: uuid)
    head :not_found if @batch.nil?
  end

  def verify_callback_token
    return if @batch.nil?

    provided = request.headers['X-Jabvox-Callback-Token'].to_s
    expected = @batch.callback_token_jabvox.to_s
    return if expected.present? && provided.present? &&
              ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end

  # Only these keys are ever read from the recipient payload — anything else n8n
  # (or an attacker) sends is dropped by strong params, never mass-assigned.
  def recipient_params
    return {} if params[:recipient].blank?

    params.require(:recipient).permit(
      :numero, :status, :contact_id, :conversation_id, :chatwoot_message_id,
      :error_code, :error_message
    )
  end

  def summary_params
    return {} if params[:summary].blank?

    params.require(:summary).permit(:total, :sent, :failed, :chunk_index, :total_chunks)
  end

  # Finds the recipient inside THIS batch — by message id when present (exact),
  # else by normalized phone. Explicit column assignment only; ids are cast to
  # integers and free-text is length-capped so a callback can only ever record a
  # sent/failed outcome, never inject unbounded or unexpected data.
  def update_recipient(data)
    recipient = find_recipient(data)
    return if recipient.nil?

    sent = data[:status].to_s == 'sent'
    recipient.update!(
      status_jabvox: sent ? 'sent' : 'failed',
      contact_id: int_or_keep(data[:contact_id], recipient.contact_id),
      conversation_id: int_or_keep(data[:conversation_id], recipient.conversation_id),
      chatwoot_message_id: int_or_keep(data[:chatwoot_message_id], recipient.chatwoot_message_id),
      error_code_jabvox: sent ? nil : truncate(data[:error_code], ERROR_CODE_LIMIT),
      error_message_jabvox: sent ? nil : truncate(data[:error_message], ERROR_MSG_LIMIT),
      sent_at_jabvox: sent ? Time.current : recipient.sent_at_jabvox
    )
  end

  def find_recipient(data)
    message_id = data[:chatwoot_message_id].presence
    if message_id
      by_message = @batch.recipients.find_by(chatwoot_message_id: message_id.to_i)
      return by_message if by_message
    end
    phone = data[:numero].to_s.gsub(/\D/, '')
    return nil if phone.blank?

    @batch.recipients.where("regexp_replace(phone_number_jabvox, '\\D', '', 'g') = ?", phone).first
  end

  def apply_summary(summary)
    chunk_index = summary[:chunk_index].to_i
    total_chunks = [summary[:total_chunks].to_i, 1].max
    @batch.recalculate_status!(final: (chunk_index + 1) >= total_chunks)
  end

  def int_or_keep(value, fallback)
    value.present? ? value.to_i : fallback
  end

  def truncate(value, limit)
    value.to_s.strip.first(limit).presence
  end
end
