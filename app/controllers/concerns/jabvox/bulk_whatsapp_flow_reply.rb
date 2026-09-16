# Flow-specific half of Jabvox::BulkWhatsappReplyStatus's reply matching (split
# out purely to stay under the module-length cop — always included alongside
# it, and relies on its #candidate_incoming_messages). A FLOW send's flow_token
# (generated at send time, see PopulateTemplateParametersService) is echoed
# back by Meta in the incoming nfm_reply, giving an exact match independent of
# WhatsApp's own reply-threading (used for every other button type instead).
module Jabvox::BulkWhatsappFlowReply
  # { chatwoot_message_id => flow_token } for every recipient whose outgoing
  # template had a FLOW button — read straight from the send's own stored
  # additional_attributes, not re-derived.
  def flow_tokens_for(recipients_with_conv)
    message_ids = recipients_with_conv.filter_map(&:chatwoot_message_id)
    return {} if message_ids.empty?

    Message.where(account_id: Current.account.id, id: message_ids)
           .pluck(:id, :additional_attributes)
           .each_with_object({}) do |(id, attrs), out|
      token = flow_token_from_additional_attributes(attrs)
      out[id] = token if token
    end
  end

  def flow_token_from_additional_attributes(attrs)
    buttons = attrs.dig('template_params', 'processed_params', 'buttons')
    buttons&.find { |b| b['type'] == 'flow' }&.dig('flow_token')
  end

  # { flow_token => the incoming nfm_reply Message that echoed it back }. See
  # Jabvox::BulkWhatsappReplyStatus#threaded_reply_by_source_id for why this
  # filters in Ruby rather than via a Postgres json operator on
  # content_attributes (same double-encoding issue applies here).
  def flow_reply_by_token(candidate_conversation_ids, tokens, since:)
    return {} if tokens.empty? || candidate_conversation_ids.empty?

    wanted = tokens.to_set
    candidate_incoming_messages(candidate_conversation_ids, since)
      .each_with_object({}) do |m, out|
      token = m.content_attributes.dig('whatsapp_flow_response', 'flow_token')
      out[token] ||= m if token && wanted.include?(token)
    end
  end
end
