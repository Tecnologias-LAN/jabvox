# Delivery/read/failed stats sourced from message_status_events (the timestamps
# Meta sends on each status transition). Split out of the builder to keep it
# focused; relies on the builder's account/outgoing scopes.
module V2::Reports::WhatsappReport::MessageStatusStats
  def status_event_counts
    # group(:status) already yields the enum's string names ("delivered"/"read"/…),
    # so no key transform is needed.
    @status_event_counts ||= MessageStatusEvent
                             .where(account_id: account.id, message_id: outgoing_messages.select(:id))
                             .group(:status).count
  end

  def agent_status_count(uid, status_name)
    MessageStatusEvent.where(account_id: account.id, status: MessageStatusEvent.statuses[status_name],
                             message_id: agent_outgoing(uid).select(:id)).count
  end

  # time-to-read of the customer: read.occurred_at − message.created_at, per
  # outgoing message the agent sent. Requires message_status_events (read).
  def customer_read_times(uid)
    reads = MessageStatusEvent.where(account_id: account.id, status: MessageStatusEvent.statuses['read'],
                                     message_id: agent_outgoing(uid).select(:id))
                              .pluck(:message_id, :occurred_at)
    return [] if reads.empty?

    created = account.messages.where(id: reads.map(&:first)).pluck(:id, :created_at).to_h
    reads.filter_map { |mid, read_at| (read_at - created[mid]).to_i if created[mid] }
  end

  def read_timestamp(message)
    MessageStatusEvent.where(message_id: message.id, status: MessageStatusEvent.statuses['read'])
                      .order(:occurred_at).first&.occurred_at
  end

  # Failures grouped by Meta error code, for the fail-rate breakdown.
  def error_breakdown
    MessageStatusEvent.where(account_id: account.id, status: MessageStatusEvent.statuses['failed'],
                             message_id: outgoing_messages.select(:id))
                      .group(:error_code).count
                      .map { |code, count| { code: code.presence || 'unknown', count: count } }
  end
end
