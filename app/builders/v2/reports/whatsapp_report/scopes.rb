# Conversation/message scopes and the filter chain (labels, batch, business) for
# the WhatsApp report. Business filters delegate to the injection-safe
# Jabvox::LeadsFilterService. Split out of the builder to keep it focused.
module V2::Reports::WhatsappReport::Scopes
  def conversations
    @conversations ||= filter_by_business(filter_by_batch(filter_by_labels(base_conversations)))
  end

  def base_conversations
    scope = account.conversations.where(inbox_id: whatsapp_inbox_ids)
    scope = scope.where(created_at: range) if range
    { inbox_id: params[:inbox_id], team_id: params[:team_id],
      status: params[:status], priority: params[:priority] }.each do |column, value|
      scope = scope.where(column => value) if value.present?
    end
    scope
  end

  def whatsapp_inbox_ids
    @whatsapp_inbox_ids ||= account.inboxes.where(channel_type: 'Channel::Whatsapp').pluck(:id)
  end

  def conversation_ids
    @conversation_ids ||= conversations.pluck(:id)
  end

  def outgoing_messages
    @outgoing_messages ||= account.messages
                                  .where(conversation_id: conversation_ids, private: false)
                                  .where(message_type: %i[outgoing template])
  end

  def incoming_messages
    @incoming_messages ||= account.messages.where(conversation_id: conversation_ids, message_type: :incoming)
  end

  def agent_outgoing(uid)
    outgoing_messages.where(sender_type: 'User', sender_id: uid)
  end

  def incoming_for_convs(conv_ids)
    account.messages.where(conversation_id: conv_ids, message_type: :incoming)
  end

  # reporting_events already stores the computed times (first_response, reply_time,
  # conversation_resolved); we only ever read them, scoped to this report's convs.
  def reporting_events
    @reporting_events ||= begin
      scope = account.reporting_events.where(conversation_id: conversation_ids)
      scope = scope.where(created_at: range) if range
      scope
    end
  end

  def reporting_values(name, uid = nil)
    scope = reporting_events.where(name: name)
    scope = scope.where(user_id: uid) if uid
    column = ActiveModel::Type::Boolean.new.cast(params[:business_hours]) ? :value_in_business_hours : :value
    scope.pluck(column).compact
  end

  def filter_by_labels(scope)
    return scope if params[:labels].blank?

    scope.tagged_with(Array(params[:labels]), any: true)
  end

  # Ties the report to a bulk-send lot: only conversations whose recipients belong
  # to that batch_uuid.
  def filter_by_batch(scope)
    return scope if params[:batch_uuid].blank?

    batch = account.jabvox_bulk_whatsapp_batches.find_by(batch_uuid_jabvox: params[:batch_uuid])
    return scope.none unless batch

    conv_ids = batch.recipients.where.not(conversation_id: nil).pluck(:conversation_id)
    scope.where(id: conv_ids)
  end

  # Business filters (campaign, affiliate, country, management state, sales…) via
  # the shared leads filter: resolves the matching leads → their contact_ids →
  # conversations of those contacts.
  def filter_by_business(scope)
    business = params[:business].presence
    return scope if business.blank?

    contact_ids = Jabvox::LeadsFilterService.new(account: account, user: nil, is_admin: true, filters: business)
                                            .scope.pluck(:contact_id).compact.uniq
    return scope.none if contact_ids.empty?

    scope.where(contact_id: contact_ids)
  end
end
