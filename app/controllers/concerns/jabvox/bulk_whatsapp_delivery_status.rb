# Resolves the WhatsApp delivery lifecycle (delivered/read + timestamps) for bulk
# send recipients by joining their chatwoot_message_id to message_status_events.
# Reply tracking (replied/not_replied) lives in Jabvox::BulkWhatsappReplyStatus —
# split out purely to stay under the module-length cop; both are included
# together by the controller. Kept in concerns so the batches controller stays
# focused on CRUD.
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

  # Aggregate delivered/read/replied counts for the batch header. `recipients`
  # is any recipients relation — batch.recipients for a single batch, or the
  # account-wide/filtered scope from the cross-batch Informes → Plantillas
  # report (see Jabvox::BulkWhatsappTemplatesReport).
  def delivery_summary(recipients)
    ids = recipients.where.not(chatwoot_message_id: nil).pluck(:chatwoot_message_id)
    delivered_read = if ids.empty?
                       { 'delivered' => 0, 'read' => 0 }
                     else
                       MessageStatusEvent.where(account_id: Current.account.id, message_id: ids).group(:status).count
                     end

    replied = first_reply_map(recipients.where.not(conversation_id: nil).where.not(sent_at_jabvox: nil)).size
    { delivered: delivered_read['delivered'].to_i, read: delivered_read['read'].to_i, replied: replied }
  end

  # status filter accepts recipient states (pending/sent/failed) plus the
  # delivery-lifecycle states (delivered/read/replied/not_replied), resolved via
  # message_status_events / the contact's first incoming message.
  # `all_recipients` is the universe to resolve delivered/read/replied against
  # (batch.recipients for one batch, or the same cross-batch scope as
  # `scope` for the Informes report) — kept separate from `scope` (already
  # filtered by other params) so status filtering doesn't narrow its own lookup.
  def filter_recipients_by_status(all_recipients, scope, status)
    return filter_by_reply_status(all_recipients, scope, status) if %w[replied not_replied].include?(status)
    return scope.where(status_jabvox: status) unless %w[delivered read].include?(status)

    ids = all_recipients.where.not(chatwoot_message_id: nil).pluck(:chatwoot_message_id)
    reached = MessageStatusEvent.where(account_id: Current.account.id, message_id: ids,
                                       status: MessageStatusEvent.statuses[status]).pluck(:message_id)
    scope.where(chatwoot_message_id: reached)
  end

  def filter_by_reply_status(all_recipients, scope, status)
    with_conv = all_recipients.where.not(conversation_id: nil).where.not(sent_at_jabvox: nil)
    replied_ids = first_reply_map(with_conv).keys
    status == 'replied' ? scope.where(id: replied_ids) : scope.where.not(id: replied_ids)
  end

  # Combina uno o varios estados (OR): la unión de los recipients que están en cualquiera
  # de los estados pedidos, reutilizando filter_recipients_by_status por estado.
  # `all_recipients` is the universe to resolve delivered/read/replied against;
  # shared by BatchesController (batch.recipients) and the cross-batch Informes
  # → Plantillas report (TemplatesReportController).
  def filter_by_statuses(all_recipients, scope, status_param)
    statuses = status_param.to_s.split(',').map(&:strip).reject(&:blank?).uniq
    return scope if statuses.empty?
    return filter_recipients_by_status(all_recipients, scope, statuses.first) if statuses.one?

    ids = statuses.flat_map { |st| filter_recipients_by_status(all_recipients, all_recipients, st).pluck(:id) }.uniq
    scope.where(id: ids)
  end

  # Delivered/read flags + timestamps for one recipient from the preloaded map.
  # reply_map is optional so callers that don't need it (e.g. delivery_summary's
  # own aggregate query) aren't forced to compute it. reply_map values are the
  # Reply struct itself (see Jabvox::BulkWhatsappReplyStatus#first_reply_map),
  # so the actual answer text (reply_text) AND how confident the match is
  # (reply_source: 'flow'/'button' are exact, 'message' is a best-effort guess)
  # can both be shown, not just whether/when.
  def recipient_delivery_fields(recipient, status_map, reply_map = {})
    events = status_map[recipient.chatwoot_message_id] || {}
    reply = reply_map[recipient.id]
    {
      chatwoot_message_id: recipient.chatwoot_message_id,
      delivered_at: events['delivered'],
      read_at: events['read'],
      delivered: events.key?('delivered'),
      read: events.key?('read'),
      replied: reply.present?,
      replied_at: reply&.created_at,
      reply_text: reply_text_for(reply),
      reply_source: reply_source_for(reply),
      reply_time_seconds: reply_time_seconds(recipient, reply&.created_at)
    }
  end

  # CSV with the full send result per recipient, including delivered/read/replied.
  # with_origin adds a "Vía de envío" column (Masivo/Individual) for the
  # cross-source Informes → Plantillas report — the per-batch report (every row
  # already the same origin) omits it, so its CSV shape doesn't change.
  def recipients_csv(scope, with_origin: false)
    rows = scope.to_a
    status_map = delivery_status_map(rows)
    reply_map = first_reply_map(rows)
    CSV.generate(headers: true) do |csv|
      headers = ['Nombre', 'Número', 'Plantilla', 'Estado', 'Entregado', 'Leído',
                 'Entregado a las', 'Leído a las', 'Respondió', 'Respondido a las',
                 'Vía de respuesta', 'Tiempo de respuesta (seg)', 'Respuesta', 'Código error',
                 'Mensaje error', 'Enviado a las', 'ID mensaje']
      headers << 'Vía de envío' if with_origin
      csv << headers
      rows.each { |r| csv << recipient_csv_row(r, status_map[r.chatwoot_message_id] || {}, reply_map[r.id], with_origin: with_origin) }
    end
  end

  def recipient_csv_row(recipient, events, reply, with_origin: false)
    row = [recipient.name_jabvox, recipient.phone_number_jabvox, recipient.template_name_jabvox,
           recipient.status_jabvox, (events.key?('delivered') ? 'Sí' : 'No'), (events.key?('read') ? 'Sí' : 'No'),
           events['delivered'], events['read'], (reply.present? ? 'Sí' : 'No'), reply&.created_at,
           reply_source_label(reply_source_for(reply)),
           reply_time_seconds(recipient, reply&.created_at), reply_text_for(reply),
           recipient.error_code_jabvox, recipient.error_message_jabvox,
           recipient.sent_at_jabvox, recipient.chatwoot_message_id]
    row << send_origin_label(recipient) if with_origin
    row
  end

  def send_origin_label(recipient)
    recipient.respond_to?(:source) && recipient.source == 'individual' ? 'Individual' : 'Masivo'
  end

  def reply_source_label(source)
    { 'flow' => 'Formulario (Flow)', 'button' => 'Botón', 'message' => 'Mensaje' }[source]
  end
end
