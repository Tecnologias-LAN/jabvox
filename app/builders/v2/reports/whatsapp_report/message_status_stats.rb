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

  # Delivered/read/failed counts and rates for one agent's outgoing messages.
  def agent_delivery_stats(uid)
    sent = agent_outgoing(uid).count
    delivered = agent_status_count(uid, 'delivered')
    read = agent_status_count(uid, 'read')
    {
      delivered: delivered,
      read: read,
      failed: agent_outgoing(uid).where(status: :failed).count,
      delivery_rate: rate(delivered, sent),
      read_rate: rate(read, delivered)
    }
  end

  # time-to-read of the customer: read.occurred_at − message.created_at, per
  # outgoing message the agent sent. Requires message_status_events (read).
  def customer_read_times(uid)
    elapsed_times_for('read', agent_outgoing(uid).select(:id))
  end

  # time-to-deliver: delivered.occurred_at − message.created_at, per agent message.
  def customer_delivery_times(uid)
    elapsed_times_for('delivered', agent_outgoing(uid).select(:id))
  end

  # Global (non-per-agent) elapsed times over all outgoing messages in scope.
  def all_read_times
    elapsed_times_for('read', outgoing_messages.select(:id))
  end

  def all_delivery_times
    elapsed_times_for('delivered', outgoing_messages.select(:id))
  end

  # Seconds between a message's created_at and its first `status` event, for every
  # message in the given id relation that reached that status.
  def elapsed_times_for(status, message_id_relation)
    events = MessageStatusEvent.where(account_id: account.id, status: MessageStatusEvent.statuses[status],
                                      message_id: message_id_relation)
                               .pluck(:message_id, :occurred_at)
    return [] if events.empty?

    created = account.messages.where(id: events.map(&:first)).pluck(:id, :created_at).to_h
    events.filter_map { |mid, at| (at - created[mid]).to_i if created[mid] }
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
