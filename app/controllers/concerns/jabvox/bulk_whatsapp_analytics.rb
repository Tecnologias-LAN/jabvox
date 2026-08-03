# Reportes agregados de envíos masivos: totales globales (enviados con éxito,
# entregados, leídos, fallidos) y series agrupadas por envío, día o semana, con
# filtro por rango de fechas. Entregado/leído se resuelven cruzando el
# chatwoot_message_id de cada destinatario con message_status_events (una query).
module Jabvox::BulkWhatsappAnalytics
  GROUP_BY = %w[batch day week].freeze

  # { totals: {...}, series: [{ key, label, ... }] } para la pestaña Reportes.
  def analytics_report
    batches = analytics_batches
    recipients = JabvoxBulkWhatsappRecipient.where(bulk_whatsapp_batch_id: batches.select(:id))
    reached = delivery_counts_for(recipients)

    {
      totals: totals_for(recipients, reached),
      group_by: analytics_group_by,
      series: series_for(batches, recipients, reached)
    }
  end

  private

  def analytics_group_by
    GROUP_BY.include?(params[:group_by].to_s) ? params[:group_by].to_s : 'batch'
  end

  # Batches de la cuenta dentro del rango (from/to en epoch segundos), más nuevos
  # primero. Sin rango: los últimos 100.
  def analytics_batches
    scope = Current.account.jabvox_bulk_whatsapp_batches.includes(:inbox, :sender_user)
    scope = scope.where(created_at: Time.zone.at(params[:from].to_i)..) if params[:from].present?
    scope = scope.where(created_at: ..Time.zone.at(params[:to].to_i)) if params[:to].present?
    scope.order(created_at: :desc).limit(500)
  end

  # { by_message: { message_id => {'delivered'=>true,'read'=>true} }, delivered:, read: }
  # en una sola query contra message_status_events.
  def delivery_counts_for(recipients)
    ids = recipients.where.not(chatwoot_message_id: nil).pluck(:chatwoot_message_id)
    return { delivered: 0, read: 0, by_message: {} } if ids.empty?

    by_message = reached_by_message(ids)
    { delivered: by_message.count { |_, s| s['delivered'] },
      read: by_message.count { |_, s| s['read'] },
      by_message: by_message }
  end

  def reached_by_message(message_ids)
    statuses = [MessageStatusEvent.statuses['delivered'], MessageStatusEvent.statuses['read']]
    pairs = MessageStatusEvent.where(account_id: Current.account.id, message_id: message_ids, status: statuses)
                              .distinct.pluck(:message_id, :status)
    by_message = Hash.new { |h, k| h[k] = {} }
    pairs.each { |mid, status| by_message[mid][status.to_s] = true }
    by_message
  end

  def totals_for(recipients, reached)
    by_status = recipients.group(:status_jabvox).count
    sent = by_status['sent'].to_i
    {
      recipients: recipients.count,
      sent: sent,
      failed: by_status['failed'].to_i,
      pending: by_status['pending'].to_i,
      delivered: reached[:delivered],
      read: reached[:read],
      delivery_rate: percentage(reached[:delivered], sent),
      read_rate: percentage(reached[:read], reached[:delivered])
    }
  end

  # Una fila por envío / día / semana con sus totales.
  def series_for(batches, recipients, reached)
    rows = recipients.select(:id, :bulk_whatsapp_batch_id, :status_jabvox, :chatwoot_message_id).to_a
    batch_meta = batches.index_by(&:id)
    grouped = rows.group_by { |r| series_key(r, batch_meta) }
    grouped.map { |key, group| series_row(key, group, reached[:by_message]) }
           .sort_by { |row| row[:key].to_s }.reverse
  end

  def series_key(recipient, batch_meta)
    return recipient.bulk_whatsapp_batch_id if analytics_group_by == 'batch'

    created = batch_meta[recipient.bulk_whatsapp_batch_id]&.created_at || Time.current
    analytics_group_by == 'week' ? created.beginning_of_week.to_date.iso8601 : created.to_date.iso8601
  end

  def series_row(key, group, by_message)
    sent = group.count { |r| r.status_jabvox == 'sent' }
    delivered = group.count { |r| reached?(r, by_message, 'delivered') }
    read = group.count { |r| reached?(r, by_message, 'read') }
    {
      key: key,
      label: series_label(key, group),
      total: group.size, sent: sent,
      failed: group.count { |r| r.status_jabvox == 'failed' },
      pending: group.count { |r| r.status_jabvox == 'pending' },
      delivered: delivered, read: read,
      delivery_rate: percentage(delivered, sent), read_rate: percentage(read, delivered)
    }
  end

  def reached?(recipient, by_message, status)
    mid = recipient.chatwoot_message_id
    mid.present? && by_message[mid]&.dig(status) ? true : false
  end

  def series_label(key, group)
    return key.to_s unless analytics_group_by == 'batch'

    batch = Current.account.jabvox_bulk_whatsapp_batches.find_by(id: key)
    batch&.file_name_jabvox.presence || batch&.template_name_jabvox.presence ||
      "##{key} · #{group.size}"
  end

  def percentage(part, whole)
    whole.to_i.zero? ? 0.0 : ((part.to_f / whole) * 100).round(1)
  end
end
