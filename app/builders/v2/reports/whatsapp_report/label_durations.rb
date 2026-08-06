# Aggregates how long each label stayed applied across the report's conversations,
# from jabvox_conversation_label_logs. Only reflects intervals recorded since the
# feature was deployed. Split out of the builder to keep it focused.
module V2::Reports::WhatsappReport::LabelDurations
  # [{ label:, total_seconds:, avg_seconds:, occurrences: }], sorted by total desc.
  def label_durations
    rows = label_logs_in_range.pluck(:label_jabvox, :applied_at_jabvox, :removed_at_jabvox)
    return [] if rows.empty?

    now = Time.current
    grouped = rows.group_by(&:first)
    grouped.map { |label, entries| label_row(label, entries, now) }
           .sort_by { |r| -r[:total_seconds] }
  end

  # Detalle por lead: qué conversaciones/leads tienen (o tuvieron) una etiqueta y
  # cuánto lleva/estuvo puesta. Si se pasa `label`, filtra a esa etiqueta.
  # [{ conversation_id, display_id, label, contact_name, contact_phone,
  #    applied_at, removed_at, active, duration_seconds }], más recientes primero.
  def label_lead_details(label = nil)
    rows = label_detail_rows(label)
    return [] if rows.empty?

    now = Time.current
    contacts = label_contacts_for(rows.map(&:first))
    convs = label_display_ids_for(rows.map(&:first))
    rows.map { |row| label_lead_row(row, contacts, convs, now) }
        .sort_by { |r| -r[:applied_at].to_i }
  end

  private

  # Logs de etiqueta cuyas conversaciones son candidatas del reporte y cuyo intervalo
  # (applied_at..removed_at) SE SOLAPA con el rango. Así aparece una etiqueta aplicada
  # antes del rango pero aún activa dentro de él, o aplicada dentro del rango, sin
  # depender de que la conversación haya tenido mensajes en el periodo.
  def label_logs_in_range
    logs = JabvoxConversationLabelLog.where(account_id: account.id,
                                            conversation_id: candidate_conversation_ids)
    return logs unless range

    # Solape: applied_at <= range.end  AND  (removed_at IS NULL OR removed_at >= range.begin)
    logs.where('applied_at_jabvox <= ?', range.end)
        .where('removed_at_jabvox IS NULL OR removed_at_jabvox >= ?', range.begin)
  end

  def label_row(label, entries, now)
    durations = entries.map { |(_l, applied, removed)| ((removed || now) - applied).to_i }
    total = durations.sum
    {
      label: label,
      total_seconds: total,
      avg_seconds: (total.to_f / durations.size).round,
      occurrences: durations.size
    }
  end

  def label_detail_rows(label)
    logs = label_logs_in_range
    logs = logs.where(label_jabvox: label) if label.present?
    logs.pluck(:conversation_id, :label_jabvox, :applied_at_jabvox, :removed_at_jabvox)
  end

  def label_lead_row(row, contacts, convs, now)
    conv_id, label, applied, removed = row
    contact = contacts[conv_id] || {}
    {
      conversation_id: conv_id,
      display_id: convs[conv_id],
      label: label,
      contact_name: contact[:name],
      contact_phone: contact[:phone],
      applied_at: applied&.to_i,
      removed_at: removed&.to_i,
      active: removed.nil?,
      duration_seconds: ((removed || now) - applied).to_i
    }
  end

  def label_contacts_for(conversation_ids)
    ids = conversation_ids.compact.uniq
    return {} if ids.empty?

    account.conversations.where(id: ids).joins(:contact)
           .pluck('conversations.id', 'contacts.name', 'contacts.phone_number')
           .to_h { |cid, name, phone| [cid, { name: name, phone: phone }] }
  end

  def label_display_ids_for(conversation_ids)
    ids = conversation_ids.compact.uniq
    return {} if ids.empty?

    account.conversations.where(id: ids).pluck(:id, :display_id).to_h
  end
end
