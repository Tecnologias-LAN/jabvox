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

  # Aggregate delivered/read counts for the batch header.
  def delivery_summary(batch)
    ids = batch.recipients.where.not(chatwoot_message_id: nil).pluck(:chatwoot_message_id)
    return { delivered: 0, read: 0 } if ids.empty?

    counts = MessageStatusEvent.where(account_id: Current.account.id, message_id: ids)
                               .group(:status).count
    { delivered: counts['delivered'].to_i, read: counts['read'].to_i }
  end

  # status filter accepts recipient states (pending/sent/failed) plus the
  # delivery-lifecycle states (delivered/read), resolved via message_status_events.
  def filter_recipients_by_status(batch, scope, status)
    return scope.where(status_jabvox: status) unless %w[delivered read].include?(status)

    ids = batch.recipients.where.not(chatwoot_message_id: nil).pluck(:chatwoot_message_id)
    reached = MessageStatusEvent.where(account_id: Current.account.id, message_id: ids,
                                       status: MessageStatusEvent.statuses[status]).pluck(:message_id)
    scope.where(chatwoot_message_id: reached)
  end

  # Delivered/read flags + timestamps for one recipient from the preloaded map.
  def recipient_delivery_fields(recipient, status_map)
    events = status_map[recipient.chatwoot_message_id] || {}
    {
      chatwoot_message_id: recipient.chatwoot_message_id,
      delivered_at: events['delivered'],
      read_at: events['read'],
      delivered: events.key?('delivered'),
      read: events.key?('read')
    }
  end

  # CSV with the full send result per recipient, including delivered/read.
  def recipients_csv(scope)
    rows = scope.to_a
    status_map = delivery_status_map(rows)
    CSV.generate(headers: true) do |csv|
      csv << ['Nombre', 'Número', 'Plantilla', 'Estado', 'Entregado', 'Leído',
              'Entregado a las', 'Leído a las', 'Código error', 'Mensaje error',
              'Enviado a las', 'ID mensaje']
      rows.each { |r| csv << recipient_csv_row(r, status_map[r.chatwoot_message_id] || {}) }
    end
  end

  def recipient_csv_row(recipient, events)
    [recipient.name_jabvox, recipient.phone_number_jabvox, recipient.template_name_jabvox,
     recipient.status_jabvox, (events.key?('delivered') ? 'Sí' : 'No'), (events.key?('read') ? 'Sí' : 'No'),
     events['delivered'], events['read'], recipient.error_code_jabvox, recipient.error_message_jabvox,
     recipient.sent_at_jabvox, recipient.chatwoot_message_id]
  end
end
