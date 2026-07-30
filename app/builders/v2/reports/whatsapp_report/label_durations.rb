# Aggregates how long each label stayed applied across the report's conversations,
# from jabvox_conversation_label_logs. Only reflects intervals recorded since the
# feature was deployed. Split out of the builder to keep it focused.
module V2::Reports::WhatsappReport::LabelDurations
  # [{ label:, total_seconds:, avg_seconds:, occurrences: }], sorted by total desc.
  def label_durations
    logs = JabvoxConversationLabelLog.where(account_id: account.id, conversation_id: conversation_ids)
    logs = logs.where(applied_at_jabvox: range) if range
    rows = logs.pluck(:label_jabvox, :applied_at_jabvox, :removed_at_jabvox)
    return [] if rows.empty?

    now = Time.current
    grouped = rows.group_by(&:first)
    grouped.map { |label, entries| label_row(label, entries, now) }
           .sort_by { |r| -r[:total_seconds] }
  end

  private

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
end
