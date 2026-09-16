require 'rails_helper'

class DummyBulkWhatsappDeliveryStatusHost
  include Jabvox::BulkWhatsappDeliveryStatus
end

describe Jabvox::BulkWhatsappDeliveryStatus do
  let(:host) { DummyBulkWhatsappDeliveryStatusHost.new }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  around do |example|
    Current.account = account
    example.run
    Current.account = nil
  end

  describe '#first_reply_map' do
    it 'maps a recipient to the first incoming message sent after the template' do
      sent_at = 1.hour.ago
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account,
                                                          conversation_id: conversation.id, sent_at_jabvox: sent_at)
      reply = create(:message, account: account, conversation: conversation, message_type: 'incoming',
                               created_at: sent_at + 5.minutes)

      map = host.first_reply_map([recipient])

      expect(map[recipient.id]).to be_within(1.second).of(reply.created_at)
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

      expect(map[recipient.id]).to be_within(1.second).of(first_reply.created_at)
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
    it 'includes replied/replied_at/reply_time_seconds alongside delivered/read' do
      sent_at = 1.hour.ago
      recipient = create(:jabvox_bulk_whatsapp_recipient, account: account, sent_at_jabvox: sent_at)
      replied_at = sent_at + 30.seconds

      fields = host.recipient_delivery_fields(recipient, {}, { recipient.id => replied_at })

      expect(fields[:replied]).to be(true)
      expect(fields[:replied_at]).to eq(replied_at)
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
