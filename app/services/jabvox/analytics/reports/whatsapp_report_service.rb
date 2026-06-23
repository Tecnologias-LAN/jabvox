# Internal analytics report for WhatsApp activity.
#
# In Jabvox (Chatwoot core) "WhatsApp" is modelled as conversations + messages
# whose inbox has channel_type 'Channel::Whatsapp'. This report scopes every
# query to a single account through ActiveRecord associations
# (account.conversations / account.messages) so it can never read another
# account's data. There is no raw SQL and no global .all.
#
# Schema notes (verified against db/schema.rb):
#   - conversations.status         enum open/resolved/pending/snoozed
#   - conversations.assignee_id -> users.id (assigned agent)
#   - messages.message_type        enum incoming/outgoing/activity/template
#   - messages.private             boolean (public messages => private = false).
#     NOTE: the column is `private`, NOT `is_private`.
#   - inboxes.channel_type = 'Channel::Whatsapp' identifies the WhatsApp inbox.
class Jabvox::Analytics::Reports::WhatsappReportService
  WHATSAPP_CHANNEL_TYPE = 'Channel::Whatsapp'.freeze

  def initialize(account:, date_from: nil, date_to: nil, filters: {})
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
    @date_from = date_from
    @date_to = date_to
    @filters = filters || {}
  end

  def call
    {
      summary: summary,
      series: daily_series,
      by_status: by_status,
      by_agent: by_agent
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Requested agent id (agent_id or user_id in @filters). Real FK: assignee_id.
  def filter_agent_id
    @filter_agent_id ||= begin
      raw = filters['agent_id'].presence || filters['user_id'].presence
      raw && raw.to_i
    end
  end

  def filter_status
    filters['status'].presence
  end

  def filter_inbox_id
    @filter_inbox_id ||= filters['inbox_id'].presence&.to_i
  end

  # IDs of this account's inboxes whose channel is WhatsApp. Always derived from
  # the account association, so the rest of the report is implicitly scoped. If
  # an inbox_id filter is given, the set is intersected with it (never widened).
  def whatsapp_inbox_ids
    @whatsapp_inbox_ids ||= begin
      ids = account.inboxes.where(channel_type: WHATSAPP_CHANNEL_TYPE).pluck(:id)
      filter_inbox_id ? ids & [filter_inbox_id] : ids
    end
  end

  # Conversations belonging to this account on WhatsApp inboxes, date-bounded.
  # Extra filters: assignee_id (agent) and status (enum).
  def conversations_scope
    scope = account.conversations.where(inbox_id: whatsapp_inbox_ids)
    scope = scope.where(assignee_id: filter_agent_id) if filter_agent_id
    scope = scope.where(status: filter_status) if filter_status
    apply_date_range(scope)
  end

  # Public, non-activity messages on this account's WhatsApp inboxes.
  # private = false keeps out internal notes; we count incoming/outgoing only.
  def messages_scope
    scope = account.messages
                   .where(inbox_id: whatsapp_inbox_ids, private: false)
                   .where(message_type: %i[incoming outgoing])
    apply_date_range(scope)
  end

  def apply_date_range(scope)
    scope = scope.where(created_at: date_from..) if date_from.present?
    scope = scope.where(created_at: ..date_to) if date_to.present?
    scope
  end

  def summary
    msgs = messages_scope
    {
      whatsapp_inboxes: whatsapp_inbox_ids.size,
      conversations: conversations_scope.count,
      messages: msgs.count,
      incoming_messages: msgs.where(message_type: :incoming).count,
      outgoing_messages: msgs.where(message_type: :outgoing).count
    }
  end

  # Conversations created per day.
  def daily_series
    conversations_scope
      .group('DATE(conversations.created_at)')
      .count
      .sort_by { |day, _| day.to_s }
      .map { |day, count| { date: day.to_s, conversations: count } }
  end

  # Conversations grouped by status (open/resolved/pending/snoozed).
  def by_status
    conversations_scope
      .group(:status)
      .count
      .map { |status, count| { status: Conversation.statuses.key(status) || status.to_s, conversations: count } }
  end

  # Conversations grouped by assigned agent. Unassigned conversations are
  # reported under a nil assignee_id so nothing is silently dropped.
  def by_agent
    counts = conversations_scope.group(:assignee_id).count
    agent_names = account.users.where(id: counts.keys.compact).pluck(:id, :name).to_h

    counts.map do |assignee_id, count|
      {
        agent_id: assignee_id,
        agent_name: assignee_id ? (agent_names[assignee_id] || "Agente ##{assignee_id}") : 'Sin asignar',
        conversations: count
      }
    end
  end
end
