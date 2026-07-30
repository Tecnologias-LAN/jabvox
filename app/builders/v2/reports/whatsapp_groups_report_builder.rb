# Builds the WhatsApp Groups report: how many groups exist, their status split,
# member counts and per-group activity (members, messages sent to the group).
# Read-only aggregation over jabvox_whatsapp_groups / _group_members and the
# group's linked conversation messages. Admin-gated via the reports controller.
class V2::Reports::WhatsappGroupsReportBuilder
  def initialize(account:, params: {})
    @account = account
    @params = params || {}
  end

  # Summary cards: totals + status breakdown + member totals.
  def summary
    groups = scoped_groups
    {
      total_groups: groups.count,
      active_groups: groups.where(status_jabvox: 'active').count,
      archived_groups: groups.where(status_jabvox: 'archived').count,
      total_members: active_members_scope(groups).count,
      avg_members_per_group: avg_members(groups),
      messages_sent: group_messages_scope(groups).count
    }
  end

  # One row per group for the table: members, messages, status, created.
  def groups
    scoped_groups.order(created_at: :desc).map do |g|
      {
        id: g.id,
        name: g.name_jabvox,
        status: g.status_jabvox,
        provider_group_id: g.provider_group_id_jabvox,
        active_members: g.active_members_count,
        max_members: JabvoxWhatsappGroup::MAX_ACTIVE_MEMBERS,
        messages_sent: messages_for(g).count,
        created_at: g.created_at
      }
    end
  end

  private

  attr_reader :account, :params

  def scoped_groups
    scope = account.jabvox_whatsapp_groups
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    scope = scope.where(created_at: range) if range
    scope
  end

  def active_members_scope(groups)
    JabvoxWhatsappGroupMember
      .where(whatsapp_group_id: groups.select(:id),
             invite_status_jabvox: JabvoxWhatsappGroup::ACTIVE_MEMBER_STATUSES)
  end

  def group_messages_scope(groups)
    conversation_ids = groups.where.not(conversation_id: nil).pluck(:conversation_id)
    return account.messages.none if conversation_ids.empty?

    scope = account.messages.where(conversation_id: conversation_ids, message_type: :outgoing)
    scope = scope.where(created_at: range) if range
    scope
  end

  def messages_for(group)
    return account.messages.none if group.conversation_id.blank?

    account.messages.where(conversation_id: group.conversation_id, message_type: :outgoing)
  end

  def avg_members(groups)
    count = groups.count
    return 0 if count.zero?

    (active_members_scope(groups).count.to_f / count).round(1)
  end

  def range
    return nil if params[:from].blank? || params[:to].blank?

    Time.zone.at(params[:from].to_i)..Time.zone.at(params[:to].to_i)
  end
end
