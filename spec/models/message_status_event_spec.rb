# frozen_string_literal: true

require 'rails_helper'

# Verifies the WhatsApp status-webhook capture (§0.3): the handler records a
# MessageStatusEvent per (message, status) with Meta's real timestamp, is
# idempotent, and splits out the Meta error code/title.
RSpec.describe MessageStatusEvent, type: :model do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, status: :sent)
  end

  # Reaches the private capture method through an allocated service instance.
  def apply_status(status)
    svc = Whatsapp::IncomingMessageBaseService.allocate
    svc.send(:update_message_with_status, message, status)
  end

  it 'records delivered/read transitions with Meta timestamps' do
    delivered_at = 1.hour.ago.to_i
    read_at = 30.minutes.ago.to_i
    apply_status({ status: 'delivered', timestamp: delivered_at.to_s })
    apply_status({ status: 'read', timestamp: read_at.to_s })

    expect(message.reload.status).to eq('read')
    delivered = message.message_status_events.find_by(status: :delivered)
    read = message.message_status_events.find_by(status: :read)
    expect(delivered.occurred_at.to_i).to eq(delivered_at)
    expect(read.occurred_at.to_i).to eq(read_at)
  end

  it 'is idempotent for the same (message, status)' do
    2.times { apply_status({ status: 'read', timestamp: 10.minutes.ago.to_i.to_s }) }
    expect(message.message_status_events.where(status: :read).count).to eq(1)
  end

  it 'captures the Meta error code and title on failure' do
    apply_status({ status: 'failed', timestamp: Time.current.to_i.to_s,
                   errors: [{ code: 131_047, title: 'Re-engagement message' }] })
    event = message.message_status_events.find_by(status: :failed)
    expect(event.error_code).to eq('131047')
    expect(event.error_title).to eq('Re-engagement message')
    expect(message.reload.external_error).to include('131047')
  end

  it 'falls back to now when the timestamp is missing/invalid' do
    freeze = Time.current
    travel_to(freeze) do
      apply_status({ status: 'delivered', timestamp: nil })
    end
    expect(message.message_status_events.find_by(status: :delivered).occurred_at).to be_within(2.seconds).of(freeze)
  end
end
