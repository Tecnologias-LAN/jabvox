# Resolves whether a bulk-send recipient replied, and when. Split out of
# Jabvox::BulkWhatsappDeliveryStatus (which owns delivered/read) purely to stay
# under the module-length cop — both are included together by the controller.
#
# A reply is matched three ways, from most to least precise (see Reply#source):
# 1. 'flow': the outgoing message's flow_token (see PopulateTemplateParametersService)
#    is echoed back by Meta in the incoming nfm_reply. Exact.
# 2. 'button': tapping any other button sets the incoming message's context.id to
#    the template's wamid (content_attributes.in_reply_to_external_id vs the
#    outgoing message's source_id). Exact — a plain typed message never carries
#    this, confirmed against a real production payload (content_attributes == {}).
# 3. 'message': nothing to correlate with, so this falls back to "first incoming
#    message in the conversation after the send" — catches free-text replies, but
#    can be a later unrelated message if the conversation got more than one send.
module Jabvox::BulkWhatsappReplyStatus
  include Jabvox::BulkWhatsappFlowReply

  Reply = Struct.new(:message, :source) do
    delegate :content, :created_at, to: :message
  end

  ReplyLookup = Struct.new(
    :flow_tokens_by_message_id, :flow_reply_by_token,
    :source_ids_by_message_id, :threaded_reply_by_source_id,
    :first_incoming_by_conversation
  )

  # Returns { recipient.id => Reply(message:, source:) }. Callers needing
  # just the timestamp call `.created_at` on the value (see
  # #recipient_delivery_fields in Jabvox::BulkWhatsappDeliveryStatus, or
  # #reply_time_seconds below) — Reply delegates it to the underlying message.
  def first_reply_map(recipients)
    with_conv = recipients.select { |r| r.conversation_id && r.sent_at_jabvox }
    return {} if with_conv.empty?

    lookup = build_reply_lookup(with_conv)

    with_conv.each_with_object({}) do |r, out|
      reply = reply_for(r, lookup)
      out[r.id] = reply if reply
    end
  end

  def build_reply_lookup(with_conv)
    conversation_ids = with_conv.map(&:conversation_id)
    earliest_sent_at = with_conv.map(&:sent_at_jabvox).min
    flow_tokens_by_message_id = flow_tokens_for(with_conv)
    source_ids_by_message_id = source_ids_for(with_conv)
    ReplyLookup.new(
      flow_tokens_by_message_id,
      flow_reply_by_token(conversation_ids, flow_tokens_by_message_id.values, since: earliest_sent_at),
      source_ids_by_message_id,
      threaded_reply_by_source_id(conversation_ids, since: earliest_sent_at),
      first_incoming_message_by_conversation(with_conv)
    )
  end

  def reply_for(recipient, lookup)
    token = lookup.flow_tokens_by_message_id[recipient.chatwoot_message_id]
    if token && (msg = lookup.flow_reply_by_token[token])
      return Reply.new(msg, 'flow')
    end

    source_id = lookup.source_ids_by_message_id[recipient.chatwoot_message_id]
    if source_id && (msg = lookup.threaded_reply_by_source_id[source_id])
      return Reply.new(msg, 'button')
    end

    first_reply = lookup.first_incoming_by_conversation[recipient.conversation_id]
    Reply.new(first_reply, 'message') if first_reply && first_reply.created_at >= recipient.sent_at_jabvox
  end

  # { chatwoot_message_id => source_id (the wamid Meta assigned the outgoing
  # template) } — needed to match an incoming reply's in_reply_to_external_id
  # back to the exact send it answered.
  def source_ids_for(recipients_with_conv)
    message_ids = recipients_with_conv.filter_map(&:chatwoot_message_id)
    return {} if message_ids.empty?

    Message.where(account_id: Current.account.id, id: message_ids).where.not(source_id: nil).pluck(:id, :source_id).to_h
  end

  # { source_id (wamid) => the incoming Message whose in_reply_to_external_id
  # points back to it } — covers a tapped quick-reply button ("Sí"/"No") and
  # any reply WhatsApp still threads to the template.
  #
  # content_attributes is a `json` column (not `jsonb`) that Rails' own `store`
  # coder double-serializes on write (confirmed: the raw column value is a
  # JSON-encoded STRING, not an object), so Postgres' ->/->> operators can never
  # see into it — they'd always return nothing, silently. Filtering candidate
  # rows by conversation/timestamp in SQL (cheap, indexed) and matching the
  # exact key in Ruby (via the normal accessor, which decodes correctly) avoids
  # relying on an operator that looks like it should work but doesn't.
  def threaded_reply_by_source_id(candidate_conversation_ids, since:)
    return {} if candidate_conversation_ids.empty?

    candidate_incoming_messages(candidate_conversation_ids, since)
      .each_with_object({}) do |m, out|
      source_id = m.content_attributes['in_reply_to_external_id']
      out[source_id] ||= m if source_id.present?
    end
  end

  # Loads only the columns first_reply_map's Ruby-side matching needs, for
  # every incoming message in the candidate conversations since the batch's
  # earliest send — shared by threaded_reply_by_source_id/flow_reply_by_token
  # so each recipient list is only fetched from the DB once per
  # first_reply_map call (see build_reply_lookup). Includes `content` (not
  # just the matching columns) because the Message this returns IS what ends
  # up as Reply#message, and reply_text_for reads its .content — omitting it
  # here previously raised ActiveModel::MissingAttributeError the first time
  # anything touched reply_text on a match found through this path.
  def candidate_incoming_messages(conversation_ids, since)
    @candidate_incoming_messages_cache ||= {}
    cache_key = [conversation_ids.sort, since]
    @candidate_incoming_messages_cache[cache_key] ||=
      Message.select(:id, :conversation_id, :content, :content_attributes, :created_at)
             .where(account_id: Current.account.id, conversation_id: conversation_ids, message_type: :incoming)
             .where('messages.created_at >= ?', since)
             .order(:created_at)
             .to_a
  end

  # { conversation_id => its first incoming Message on/after the earliest send
  # in this batch }. Reuses the same candidate set as
  # threaded_reply_by_source_id/flow_reply_by_token (see
  # candidate_incoming_messages) so this doesn't re-query; the per-recipient
  # sent_at_jabvox check happens in the caller.
  def first_incoming_message_by_conversation(recipients_with_conv)
    conversation_ids = recipients_with_conv.map(&:conversation_id)
    earliest_sent_at = recipients_with_conv.map(&:sent_at_jabvox).min

    candidate_incoming_messages(conversation_ids, earliest_sent_at)
      .each_with_object({}) { |m, out| out[m.conversation_id] ||= m }
  end

  # Seconds between the template send and the contact's first reply, or nil
  # while there isn't one (still waiting) or the send has no timestamp yet.
  # Accepts either a replied_at Time (legacy call sites) or a Reply/Message.
  def reply_time_seconds(recipient, replied_at_or_reply)
    replied_at = replied_at_or_reply.respond_to?(:created_at) ? replied_at_or_reply.created_at : replied_at_or_reply
    return nil unless replied_at && recipient.sent_at_jabvox

    (replied_at - recipient.sent_at_jabvox).round
  end

  # Best-effort readable text of what the contact answered, for a Reply
  # returned by first_reply_map:
  #   - a completed WhatsApp Flow -> the same "campo: valor" summary rendered in
  #     the message's own content (see Whatsapp::IncomingMessageServiceHelpers).
  #   - a tapped quick-reply button, or any plain text reply -> its content.
  # Never raises on a message with no content (e.g. a bare attachment).
  def reply_text_for(reply)
    return nil if reply.nil?

    reply.content.presence
  end

  # 'flow' | 'button' | 'message' | nil — see the Reply matching precedence
  # comment above first_reply_map. Exposed so the report can tell the agent
  # exactly how confident this "replied" flag is: 'flow'/'button' are exact
  # (WhatsApp itself linked the reply to this send), 'message' is a
  # best-effort guess (first incoming message afterwards, possibly unrelated).
  def reply_source_for(reply)
    reply&.source
  end
end
