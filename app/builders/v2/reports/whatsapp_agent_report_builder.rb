# Builds the per-agent WhatsApp report: message delivery/read stats, response
# and read times, SLA and funnel. Reuses what already exists — reporting_events
# for times (first_response / reply_time / conversation_resolved), messages.status
# + message_status_events for delivery/read/timestamps, CSAT for satisfaction —
# and never recomputes a time that reporting_events already stores.
#
# Filters (all optional): from/to, inbox_id, agent_ids[], team_id, labels[],
# status, priority, business_hours, sla_seconds, batch_uuid (ties the report to a
# bulk-send lot), plus business filters delegated to Jabvox::LeadsFilterService.
#
# Times are reported as median + average + p90 (median is the headline — the
# long tails skew the average). "read"/"delivered" rely on Meta read receipts:
# if the customer disables them, those transitions never arrive and the message
# stays at the last known state (surfaced as approximate in the UI).
class V2::Reports::WhatsappAgentReportBuilder
  include V2::Reports::WhatsappReport::Scopes
  include V2::Reports::WhatsappReport::TemplateFilter
  include V2::Reports::WhatsappReport::AgentDetail
  include V2::Reports::WhatsappReport::MessageStatusStats
  include V2::Reports::WhatsappReport::MessageTypeBreakdown
  include V2::Reports::WhatsappReport::LabelDurations
  include V2::Reports::WhatsappReport::Stats

  # Meta 24h service window and default SLA (overridable via params[:sla_seconds]).
  SERVICE_WINDOW = 24.hours
  DEFAULT_SLA = 5.minutes.to_i

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  # Per-agent table: one row per account user with volume, delivery/read rates,
  # times (median/avg/p90) and SLA.
  def agents
    users = @account.users.select(:id, :name, :email).index_by(&:id)
    rows = users.keys.map { |uid| agent_row(uid, users[uid]) }
    # Solo agentes con alguna actividad (enviaron, recibieron o tuvieron
    # conversaciones asignadas): evita una tabla llena de ceros que parece vacía.
    sort_rows(rows.select { |r| agent_active?(r) })
  end

  # Global totals + funnel (sent → delivered → read → responded → resolved) for
  # the summary cards and the business study.
  def summary
    sent = outgoing_messages.count
    delivered = status_event_counts['delivered'] || 0
    read = status_event_counts['read'] || 0
    failed = status_event_counts['failed'] || 0
    volume_summary(sent, delivered, read, failed).merge(
      time_summary,
      funnel: funnel(sent, delivered, read),
      error_breakdown: error_breakdown
    )
  end

  # Agents ranked by a metric. metric: first_response | first_read | read_rate |
  # resolution | volume | sla. order: 'asc' | 'desc'.
  def rankings(metric:, order: 'desc')
    key = ranking_key(metric)
    rows = agents.filter_map do |r|
      value = ranking_value(r[key])
      next if value.nil?

      { id: r[:id], name: r[:name], value: value }
    end
    rows.sort_by! { |r| r[:value] }
    rows.reverse! if order.to_s == 'desc'
    rows
  end

  # Per-turn, multi-agent timeline of one conversation: reconstructs the sequence
  # of customer messages → who read it and when → who replied and how long it
  # took → assignment handoffs → who resolved. This is the drill-down that shows
  # "Agent 1 took X to read; Agent 2 replied after Y; Agent 3 never replied".
  def conversation_timeline(conversation_id)
    conv = account.conversations.find(conversation_id)
    msgs = conv.messages.where(private: false)
               .where(message_type: %i[incoming outgoing template activity])
               .order(:created_at, :id)
    {
      conversation_id: conv.display_id,
      assignee_id: conv.assignee_id,
      handoffs: count_handoffs(msgs),
      turns: build_turns(msgs),
      resolved_by: reporting_events.where(conversation_id: conv.id, name: 'conversation_resolved')
                                   .order(:created_at).last&.user_id
    }
  end

  private

  attr_reader :account, :params

  def volume_summary(sent, delivered, read, failed)
    {
      sent: sent, delivered: delivered, read: read, failed: failed,
      received: incoming_messages.count,
      templates: outgoing_messages.where(message_type: :template).count,
      media_sent: outgoing_media_count,
      responded: responded_conversations_count,
      resolved: resolved_conversations_count,
      delivery_rate: rate(delivered, sent),
      read_rate: rate(read, delivered),
      fail_rate: rate(failed, sent),
      incoming_by_type: incoming_breakdown,
      outgoing_by_type: outgoing_breakdown
    }
  end

  def time_summary
    {
      first_response: time_stats(reporting_values('first_response')),
      resolution: time_stats(reporting_values('conversation_resolved')),
      time_to_deliver: time_stats(all_delivery_times),
      time_to_read: time_stats(all_read_times)
    }
  end

  # A "turn" pairs a customer inbound with the agent reply that followed (if any),
  # capturing the responder and the response delay. Consecutive inbounds with no
  # reply yield a turn with responder=nil (the "no one replied" case).
  def build_turns(msgs)
    turns = []
    pending_inbound = nil
    msgs.each do |m|
      if m.incoming?
        # Close a previous unanswered inbound before opening a new one.
        turns << unanswered_turn(pending_inbound) if pending_inbound
        pending_inbound = m
      elsif agent_reply?(m)
        turns << answered_turn(pending_inbound, m)
        pending_inbound = nil
      end
    end
    turns << unanswered_turn(pending_inbound) if pending_inbound
    turns
  end

  def agent_reply?(message)
    (message.outgoing? || message.template?) && message.sender_type == 'User'
  end

  def answered_turn(inbound, reply)
    {
      customer_message_at: inbound&.created_at,
      responder_id: reply.sender_id,
      replied_at: reply.created_at,
      response_seconds: inbound ? (reply.created_at - inbound.created_at).to_i : nil,
      read_by_at: read_timestamp(reply),
      status: 'answered'
    }
  end

  def unanswered_turn(inbound)
    { customer_message_at: inbound.created_at, responder_id: nil, replied_at: nil,
      response_seconds: nil, read_by_at: nil, status: 'unanswered' }
  end

  def count_handoffs(msgs)
    msgs.select(&:activity?).count { |m| m.content.to_s.match?(/asign|assign/i) }
  end

  # ── Per-agent row ────────────────────────────────────────────────────────
  def agent_row(uid, user)
    convs = agent_conversation_ids(uid)
    { id: uid, name: user&.name, email: user&.email }
      .merge(agent_volume(uid, convs))
      .merge(agent_times(uid))
      .merge(sla_pct: sla_pct(uid), csat_avg: csat_avg[uid])
  end

  def agent_volume(uid, convs)
    breakdown = type_breakdown(agent_outgoing(uid))
    {
      conversations_assigned: convs.size,
      conversations_handled: handled_count(uid, convs),
      conversations_resolved: resolved_by_agent[uid] || 0,
      no_reply: no_reply_count(uid, convs),
      sent: agent_outgoing(uid).count,
      templates: agent_outgoing(uid).where(message_type: :template).count,
      media_sent: breakdown[:total] - breakdown[:text],
      received: incoming_for_convs(convs).count
    }.merge(agent_delivery_stats(uid))
  end

  def agent_times(uid)
    {
      first_response: time_stats(reporting_values('first_response', uid)),
      reply_time: time_stats(reporting_values('reply_time', uid)),
      resolution: time_stats(reporting_values('conversation_resolved', uid)),
      time_to_deliver: time_stats(customer_delivery_times(uid)),
      time_to_read: time_stats(customer_read_times(uid))
    }
  end

  # ── Aggregations by agent ────────────────────────────────────────────────
  def agent_conversation_ids(uid)
    @assigned_by_agent ||= conversations.where.not(assignee_id: nil).pluck(:assignee_id, :id)
                                        .group_by(&:first).transform_values { |v| v.map(&:last) }
    @assigned_by_agent[uid] || []
  end

  def handled_count(uid, convs)
    return 0 if convs.empty?

    account.messages.where(conversation_id: convs, sender_type: 'User', sender_id: uid, private: false)
           .where(message_type: %i[outgoing template]).distinct.count(:conversation_id)
  end

  # No-reply: assigned to the agent but no outgoing message from THAT agent.
  def no_reply_count(uid, convs)
    convs.size - handled_count(uid, convs)
  end

  def resolved_by_agent
    @resolved_by_agent ||= reporting_events.where(name: 'conversation_resolved')
                                           .group(:user_id).count
  end

  def responded_conversations_count
    reporting_events.where(name: 'first_response').distinct.count(:conversation_id)
  end

  def resolved_conversations_count
    conversations.resolved.count
  end

  # ── Funnel ─────────────────────────────────────────────────────────────────
  def funnel(sent, delivered, read)
    [
      { step: 'sent', value: sent },
      { step: 'delivered', value: delivered },
      { step: 'read', value: read },
      { step: 'responded', value: responded_conversations_count },
      { step: 'resolved', value: resolved_conversations_count }
    ]
  end
end
