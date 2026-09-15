# Resolves the WhatsApp delivery lifecycle (delivered/read + timestamps) for bulk
# send recipients by joining their chatwoot_message_id to message_status_events.
# Kept in a concern so the batches controller stays focused on CRUD.
module Jabvox::BulkWhatsappDeliveryStatus
  # One query for all recipients' delivered/read events, keyed by
  # chatwoot_message_id: { message_id => { 'delivered' => time, 'read' => time } }.
  def delivery_status_map(recipients)
    message_ids = recipients.filter_map(&:chatwoot_message_id)
    return {} if message_ids.empty?

    map = Hash.new { |h, k| h[k] = {} }
    MessageStatusEvent.where(account_id: Current.account.id, message_id: message_ids)
                      .where(status: [MessageStatusEvent.statuses['delivered'], MessageStatusEvent.statuses['read']])
                      .pluck(:message_id, :status, :occurred_at)
                      .each { |mid, status, at| map[mid][status.to_s] = at }
    map
  end

  # First INCOMING message (contact's reply) in each recipient's conversation
  # AFTER the template was sent — keyed by conversation_id: { conversation_id =>
  # created_at }. "Replied" means the contact wrote back at all, not that they
  # replied specifically to the template (WhatsApp gives no such linkage), so we
  # take the first incoming message after sent_at_jabvox as the reply signal.
  # One query per distinct sent_at avoids an N+1 while still respecting each
  # recipient's own send time as the reply-window start.
  def first_reply_map(recipients)
    with_conv = recipients.select { |r| r.conversation_id && r.sent_at_jabvox }
    return {} if with_conv.empty?

    first_incoming_by_conversation = first_incoming_message_times(with_conv)

    with_conv.each_with_object({}) do |r, out|
      first_reply_at = first_incoming_by_conversation[r.conversation_id]
      out[r.id] = first_reply_at if first_reply_at && first_reply_at >= r.sent_at_jabvox
    end
  end

  # { conversation_id => created_at of its first incoming message on/after the
  # earliest send in this batch }. One query for every recipient avoids an N+1;
  # the per-recipient sent_at_jabvox check happens in the caller.
  def first_incoming_message_times(recipients_with_conv)
    conversation_ids = recipients_with_conv.map(&:conversation_id)
    earliest_sent_at = recipients_with_conv.map(&:sent_at_jabvox).min

    map = {}
    Message.where(account_id: Current.account.id, conversation_id: conversation_ids, message_type: :incoming)
           .where('messages.created_at >= ?', earliest_sent_at)
           .order(:created_at)
           .pluck(:conversation_id, :created_at)
           .each { |conv_id, created_at| map[conv_id] ||= created_at }
    map
  end

  # Aggregate delivered/read/replied counts for the batch header.
  def delivery_summary(batch)
    ids = batch.recipients.where.not(chatwoot_message_id: nil).pluck(:chatwoot_message_id)
    delivered_read = if ids.empty?
                       { 'delivered' => 0, 'read' => 0 }
                     else
                       MessageStatusEvent.where(account_id: Current.account.id, message_id: ids).group(:status).count
                     end

    replied = first_reply_map(batch.recipients.where.not(conversation_id: nil).where.not(sent_at_jabvox: nil)).size
    { delivered: delivered_read['delivered'].to_i, read: delivered_read['read'].to_i, replied: replied }
  end

  # status filter accepts recipient states (pending/sent/failed) plus the
  # delivery-lifecycle states (delivered/read/replied/not_replied), resolved via
  # message_status_events / the contact's first incoming message.
  def filter_recipients_by_status(batch, scope, status)
    return filter_by_reply_status(batch, scope, status) if %w[replied not_replied].include?(status)
    return scope.where(status_jabvox: status) unless %w[delivered read].include?(status)

    ids = batch.recipients.where.not(chatwoot_message_id: nil).pluck(:chatwoot_message_id)
    reached = MessageStatusEvent.where(account_id: Current.account.id, message_id: ids,
                                       status: MessageStatusEvent.statuses[status]).pluck(:message_id)
    scope.where(chatwoot_message_id: reached)
  end

  def filter_by_reply_status(batch, scope, status)
    all_with_conv = batch.recipients.where.not(conversation_id: nil).where.not(sent_at_jabvox: nil)
    replied_ids = first_reply_map(all_with_conv).keys
    status == 'replied' ? scope.where(id: replied_ids) : scope.where.not(id: replied_ids)
  end

  # Delivered/read flags + timestamps for one recipient from the preloaded map.
  # reply_map is optional so callers that don't need it (e.g. delivery_summary's
  # own aggregate query) aren't forced to compute it.
  def recipient_delivery_fields(recipient, status_map, reply_map = {})
    events = status_map[recipient.chatwoot_message_id] || {}
    replied_at = reply_map[recipient.id]
    {
      chatwoot_message_id: recipient.chatwoot_message_id,
      delivered_at: events['delivered'],
      read_at: events['read'],
      delivered: events.key?('delivered'),
      read: events.key?('read'),
      replied: replied_at.present?,
      replied_at: replied_at,
      reply_time_seconds: reply_time_seconds(recipient, replied_at)
    }
  end

  # Seconds between the template send and the contact's first reply, or nil
  # while there isn't one (still waiting) or the send has no timestamp yet.
  def reply_time_seconds(recipient, replied_at)
    return nil unless replied_at && recipient.sent_at_jabvox

    (replied_at - recipient.sent_at_jabvox).round
  end

  # CSV with the full send result per recipient, including delivered/read/replied.
  def recipients_csv(scope)
    rows = scope.to_a
    status_map = delivery_status_map(rows)
    reply_map = first_reply_map(rows)
    CSV.generate(headers: true) do |csv|
      csv << ['Nombre', 'Número', 'Plantilla', 'Estado', 'Entregado', 'Leído',
              'Entregado a las', 'Leído a las', 'Respondió', 'Respondido a las',
              'Tiempo de respuesta (seg)', 'Código error', 'Mensaje error',
              'Enviado a las', 'ID mensaje']
      rows.each { |r| csv << recipient_csv_row(r, status_map[r.chatwoot_message_id] || {}, reply_map[r.id]) }
    end
  end

  def recipient_csv_row(recipient, events, replied_at)
    [recipient.name_jabvox, recipient.phone_number_jabvox, recipient.template_name_jabvox,
     recipient.status_jabvox, (events.key?('delivered') ? 'Sí' : 'No'), (events.key?('read') ? 'Sí' : 'No'),
     events['delivered'], events['read'], (replied_at.present? ? 'Sí' : 'No'), replied_at,
     reply_time_seconds(recipient, replied_at), recipient.error_code_jabvox, recipient.error_message_jabvox,
     recipient.sent_at_jabvox, recipient.chatwoot_message_id]
  end
end
