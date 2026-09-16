require 'rails_helper'

class DummyBulkWhatsappReplyStatusHost
  include Jabvox::BulkWhatsappReplyStatus
  include Jabvox::BulkWhatsappDeliveryStatus
end

describe Jabvox::BulkWhatsappReplyStatus do
  let(:host) { DummyBulkWhatsappReplyStatusHost.new }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  around do |example|
    Current.account = account
    example.run
    Current.account = nil
  end

  # Builds the outgoing template Message a recipient points to via
  # chatwoot_message_id, optionally with a FLOW button's flow_token stored in
  # additional_attributes the same way the real send does. additional_attributes
  # is set via update_column AFTER creation (not passed to the factory) so it
  # doesn't run through Message's after_create_commit hooks (template/automation
  # hooks that inspect additional_attributes at creation time) — those are
  # irrelevant here and only add unrelated failure modes to these specs.
  def outgoing_template_message(flow_token: nil, source_id: nil)
    buttons = flow_token ? [{ 'type' => 'flow', 'flow_token' => flow_token }] : nil
    message = create(:message, account: account, conversation: conversation, message_type: 'outgoing', source_id: source_id)
    message.update_column( # rubocop:disable Rails/SkipsModelValidations -- test setup only, avoids re-triggering create hooks
      :additional_attributes, { 'template_params' => { 'processed_params' => { 'buttons' => buttons }.compact } }
    )
    message
  end

  describe '#first_reply_map' do
    context 'when there is no flow_token and no threaded reply available (fallback)' do
      it 'maps a recipient to the first incoming message sent after the template' do
        sent_at = 1.hour.ago
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account,
                                                            conversation_id: conversation.id, sent_at_jabvox: sent_at)
        reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                 created_at: sent_at + 5.minutes)

        map = host.first_reply_map([recipient])

        expect(map[recipient.id]&.created_at).to be_within(1.second).of(reply.created_at)
      end

      it 'ignores an incoming message that arrived BEFORE the template was sent' do
        sent_at = 1.hour.ago
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account,
                                                            conversation_id: conversation.id, sent_at_jabvox: sent_at)
        create(:message, account: account, conversation: conversation, message_type: 'incoming',
                         created_at: sent_at - 5.minutes)

        map = host.first_reply_map([recipient])

        expect(map).not_to have_key(recipient.id)
      end

      it 'ignores outgoing messages in the same conversation' do
        sent_at = 1.hour.ago
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account,
                                                            conversation_id: conversation.id, sent_at_jabvox: sent_at)
        create(:message, account: account, conversation: conversation, message_type: 'outgoing',
                         created_at: sent_at + 5.minutes)

        map = host.first_reply_map([recipient])

        expect(map).not_to have_key(recipient.id)
      end

      it 'picks the EARLIEST incoming message, not the latest' do
        sent_at = 1.hour.ago
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account,
                                                            conversation_id: conversation.id, sent_at_jabvox: sent_at)
        first_reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                       created_at: sent_at + 2.minutes)
        create(:message, account: account, conversation: conversation, message_type: 'incoming',
                         created_at: sent_at + 20.minutes)

        map = host.first_reply_map([recipient])

        expect(map[recipient.id]&.created_at).to be_within(1.second).of(first_reply.created_at)
      end

      it 'does not leak a reply from a DIFFERENT conversation sharing no recipient link' do
        other_contact = create(:contact, account: account)
        other_conversation = create(:conversation, account: account, contact: other_contact)
        sent_at = 1.hour.ago
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account,
                                                            conversation_id: conversation.id, sent_at_jabvox: sent_at)
        create(:message, account: account, conversation: other_conversation, message_type: 'incoming',
                         created_at: sent_at + 5.minutes)

        expect(host.first_reply_map([recipient])).to eq({})
      end
    end

    context 'when the send had a FLOW button' do
      it 'matches the reply by flow_token, not by conversation timing' do
        sent_at = 1.hour.ago
        outgoing = outgoing_template_message(flow_token: 'tok-abc123')
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                            sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
        flow_reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                      created_at: sent_at + 3.minutes,
                                      content_attributes: { whatsapp_flow_response: { 'flow_token' => 'tok-abc123', 'answer' => 'yes' } })

        map = host.first_reply_map([recipient])

        expect(map[recipient.id]&.created_at).to be_within(1.second).of(flow_reply.created_at)
      end

      it 'falls back to the plain-message match (not the flow match) for a reply with no matching flow_token' do
        # This is the real-world "answered with free text instead of tapping
        # the button" case: no flow_token means no exact match, but the
        # contact DID write back, so it must still count as replied — just
        # via the less-precise 'message' source, never mislabeled as 'flow'.
        sent_at = 1.hour.ago
        outgoing = outgoing_template_message(flow_token: 'tok-abc123')
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                            sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
        plain_reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                       created_at: sent_at + 3.minutes)

        map = host.first_reply_map([recipient])

        expect(map[recipient.id].source).to eq('message')
        expect(map[recipient.id].created_at).to be_within(1.second).of(plain_reply.created_at)
      end

      it 'does not confuse two different recipients whose sends used different flow_tokens' do
        # Separate conversations: sharing one conversation would let the
        # plain-message fallback attribute recipient_b's flow reply to
        # recipient_a too (see the module doc on the fallback's precision
        # limits) — this example is specifically about the flow-token match,
        # not about fallback ambiguity.
        other_contact = create(:contact, account: account)
        other_conversation = create(:conversation, account: account, contact: other_contact)
        sent_at = 1.hour.ago
        outgoing_a = outgoing_template_message(flow_token: 'tok-a')
        outgoing_b = create(:message, account: account, conversation: other_conversation, message_type: 'outgoing')
        outgoing_b.update_column( # rubocop:disable Rails/SkipsModelValidations -- test setup only
          :additional_attributes, { 'template_params' => { 'processed_params' => { 'buttons' => [{ 'type' => 'flow', 'flow_token' => 'tok-b' }] } } }
        )
        recipient_a = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                              sent_at_jabvox: sent_at, chatwoot_message_id: outgoing_a.id)
        recipient_b = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: other_conversation.id,
                                                              sent_at_jabvox: sent_at, chatwoot_message_id: outgoing_b.id)
        reply_b = create(:message, account: account, conversation: other_conversation, message_type: 'incoming',
                                   created_at: sent_at + 2.minutes,
                                   content_attributes: { whatsapp_flow_response: { 'flow_token' => 'tok-b' } })

        map = host.first_reply_map([recipient_a, recipient_b])

        expect(map).not_to have_key(recipient_a.id)
        expect(map[recipient_b.id].source).to eq('flow')
        expect(map[recipient_b.id].created_at).to be_within(1.second).of(reply_b.created_at)
      end
    end

    # A quick-reply button ("Sí"/"No") carries no flow_token, but WhatsApp threads
    # the reply to the template via context.id (Jabvox stores it as
    # content_attributes.in_reply_to_external_id), matched against the outgoing
    # message's own source_id (the wamid Meta assigned it).
    context 'when the send had a QUICK_REPLY button (no flow_token, but WhatsApp threads the reply)' do
      it 'matches the reply by in_reply_to_external_id -> source_id' do
        sent_at = 1.hour.ago
        outgoing = outgoing_template_message(source_id: 'wamid.OUTGOING123')
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                            sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
        button_reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                        created_at: sent_at + 90.seconds,
                                        content_attributes: { in_reply_to_external_id: 'wamid.OUTGOING123' })

        map = host.first_reply_map([recipient])

        expect(map[recipient.id]&.created_at).to be_within(1.second).of(button_reply.created_at)
      end

      it 'does not confuse two recipients whose templates have different source_ids' do
        # Separate conversations so recipient_b's lack of a threaded match can't
        # be masked by the "first incoming in conversation" fallback picking up
        # recipient_a's reply — that fallback is conversation-scoped by design
        # (see #prefers the flow_token match over a threaded in_reply_to match
        # and the module doc), so two recipients sharing one conversation with
        # only one threaded reply between them is a genuinely ambiguous case,
        # not what this example is testing.
        other_contact = create(:contact, account: account)
        other_conversation = create(:conversation, account: account, contact: other_contact)
        sent_at = 1.hour.ago
        outgoing_a = outgoing_template_message(source_id: 'wamid.A')
        outgoing_b = create(:message, account: account, conversation: other_conversation, message_type: 'outgoing', source_id: 'wamid.B')
        recipient_a = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                              sent_at_jabvox: sent_at, chatwoot_message_id: outgoing_a.id)
        recipient_b = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: other_conversation.id,
                                                              sent_at_jabvox: sent_at, chatwoot_message_id: outgoing_b.id)
        reply_a = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                   created_at: sent_at + 1.minute,
                                   content_attributes: { in_reply_to_external_id: 'wamid.A' })

        map = host.first_reply_map([recipient_a, recipient_b])

        expect(map[recipient_a.id]&.created_at).to be_within(1.second).of(reply_a.created_at)
        expect(map).not_to have_key(recipient_b.id)
      end

      it 'prefers the threaded reply over a later unrelated incoming message' do
        sent_at = 1.hour.ago
        outgoing = outgoing_template_message(source_id: 'wamid.OUTGOING123')
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                            sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
        button_reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                        created_at: sent_at + 90.seconds,
                                        content_attributes: { in_reply_to_external_id: 'wamid.OUTGOING123' })
        # A later plain message (not threaded) must not override the real, threaded reply.
        create(:message, account: account, conversation: conversation, message_type: 'incoming',
                         created_at: sent_at + 10.minutes)

        map = host.first_reply_map([recipient])

        expect(map[recipient.id]&.created_at).to be_within(1.second).of(button_reply.created_at)
      end
    end

    # Acceptance scenario reported by the user: a MARKETING template with two
    # QUICK_REPLY buttons ("Quiero avanzar" / "Tengo dudas"). Tapping a button
    # must be reported as an exact ('button') match with its own label as the
    # reply text; replying with free text INSTEAD of tapping a button must
    # still count as replied (source 'message'), showing whatever the contact
    # actually typed.
    context "when the template has QUICK_REPLY buttons ('Quiero avanzar' / 'Tengo dudas')" do
      it 'reports a tapped button as an exact match, with the button label as reply_text' do
        sent_at = 1.hour.ago
        outgoing = outgoing_template_message(source_id: 'wamid.PROPUESTA1')
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                            sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
        create(:message, account: account, conversation: conversation, message_type: 'incoming',
                         content: 'Tengo dudas', created_at: sent_at + 90.seconds,
                         content_attributes: { in_reply_to_external_id: 'wamid.PROPUESTA1' })

        map = host.first_reply_map([recipient])
        reply = map[recipient.id]

        expect(reply.source).to eq('button')
        expect(host.reply_text_for(reply)).to eq('Tengo dudas')
      end

      it 'still reports a free-text reply (no button tapped) as replied, via the message fallback' do
        sent_at = 1.hour.ago
        outgoing = outgoing_template_message(source_id: 'wamid.PROPUESTA2')
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                            sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
        # No content_attributes.in_reply_to_external_id here — confirmed
        # against a real production payload that a plain typed reply (no
        # button tapped, no explicit WhatsApp "reply to") carries no context.
        create(:message, account: account, conversation: conversation, message_type: 'incoming',
                         content: 'no he tenido tiempo de revisarla', created_at: sent_at + 90.seconds)

        map = host.first_reply_map([recipient])
        reply = map[recipient.id]

        expect(reply.source).to eq('message')
        expect(host.reply_text_for(reply)).to eq('no he tenido tiempo de revisarla')
      end
    end

    context 'when both a flow_token and a threaded in_reply_to match are present' do
      it 'prefers the flow_token match over a threaded in_reply_to match' do
        sent_at = 1.hour.ago
        outgoing = outgoing_template_message(flow_token: 'tok-abc', source_id: 'wamid.OUTGOING123')
        recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                            sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
        # Both signals present; the earlier, less-precise in_reply_to match must lose.
        threaded_reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                          created_at: sent_at + 1.minute,
                                          content_attributes: { in_reply_to_external_id: 'wamid.OUTGOING123' })
        flow_reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                                      created_at: sent_at + 5.minutes,
                                      content_attributes: { whatsapp_flow_response: { 'flow_token' => 'tok-abc' } })

        map = host.first_reply_map([recipient])

        expect(map[recipient.id]&.created_at).to be_within(1.second).of(flow_reply.created_at)
        expect(map[recipient.id]&.created_at).not_to be_within(1.second).of(threaded_reply.created_at)
      end
    end

    it 'skips recipients with no conversation_id' do
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: nil,
                                                          sent_at_jabvox: 1.hour.ago)

      expect(host.first_reply_map([recipient])).to eq({})
    end

    it 'skips recipients with no sent_at_jabvox (never actually sent)' do
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conversation.id,
                                                          sent_at_jabvox: nil)
      create(:message, account: account, conversation: conversation, message_type: 'incoming')

      expect(host.first_reply_map([recipient])).to eq({})
    end

    it 'returns {} without querying when given no recipients' do
      expect(host.first_reply_map([])).to eq({})
    end

    it 'handles a large batch with mixed reply types without an N+1 (stress)' do
      sent_at = 2.hours.ago
      recipients = []

      100.times do |i|
        conv = create(:conversation, account: account, contact: contact)
        case i % 4
        when 0 # flow reply
          outgoing = outgoing_template_message(flow_token: "tok-#{i}")
          r = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conv.id,
                                                      sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
          create(:message, account: account, conversation: conv, message_type: 'incoming', created_at: sent_at + 1.minute,
                           content_attributes: { whatsapp_flow_response: { 'flow_token' => "tok-#{i}" } })
        when 1 # quick-reply / threaded reply
          outgoing = outgoing_template_message(source_id: "wamid.#{i}")
          r = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conv.id,
                                                      sent_at_jabvox: sent_at, chatwoot_message_id: outgoing.id)
          create(:message, account: account, conversation: conv, message_type: 'incoming', created_at: sent_at + 1.minute,
                           content_attributes: { in_reply_to_external_id: "wamid.#{i}" })
        when 2 # plain fallback reply
          r = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conv.id, sent_at_jabvox: sent_at)
          create(:message, account: account, conversation: conv, message_type: 'incoming', created_at: sent_at + 1.minute)
        else # no reply at all
          r = create(:jabvox_bulk_whatsapp_recipient, account: account, conversation_id: conv.id, sent_at_jabvox: sent_at)
        end
        recipients << r
      end

      query_count = 0
      callback = ->(*) { query_count += 1 }
      map = nil
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        map = host.first_reply_map(recipients)
      end

      expect(map.size).to eq(75) # 3 out of every 4 recipients got a reply
      expect(query_count).to be <= 6 # fixed, small number of queries regardless of recipient count
    end
  end

  describe '#reply_time_seconds' do
    it 'computes the elapsed seconds between send and reply' do
      sent_at = Time.zone.parse('2026-01-01 10:00:00')
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, sent_at_jabvox: sent_at)
      replied_at = sent_at + 90.seconds

      expect(host.reply_time_seconds(recipient, replied_at)).to eq(90)
    end

    it 'returns nil when there is no reply yet' do
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, sent_at_jabvox: Time.current)

      expect(host.reply_time_seconds(recipient, nil)).to be_nil
    end

    it 'returns nil when the recipient was never actually sent' do
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, sent_at_jabvox: nil)

      expect(host.reply_time_seconds(recipient, Time.current)).to be_nil
    end
  end

  describe '#recipient_delivery_fields' do
    it 'includes replied/replied_at/reply_text/reply_source/reply_time_seconds alongside delivered/read' do
      sent_at = 1.hour.ago
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, sent_at_jabvox: sent_at)
      message = create(:message, account: account, message_type: 'incoming', content: 'Sí, me interesa',
                                 created_at: sent_at + 30.seconds)
      reply = Jabvox::BulkWhatsappReplyStatus::Reply.new(message, 'button')

      fields = host.recipient_delivery_fields(recipient, {}, { recipient.id => reply })

      expect(fields[:replied]).to be(true)
      expect(fields[:replied_at]).to be_within(1.second).of(message.created_at)
      expect(fields[:reply_text]).to eq('Sí, me interesa')
      expect(fields[:reply_source]).to eq('button')
      expect(fields[:reply_time_seconds]).to eq(30)
    end

    it 'marks replied as false when the recipient has no entry in reply_map' do
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, sent_at_jabvox: 1.hour.ago)

      fields = host.recipient_delivery_fields(recipient, {}, {})

      expect(fields[:replied]).to be(false)
      expect(fields[:replied_at]).to be_nil
      expect(fields[:reply_time_seconds]).to be_nil
    end
  end
end
