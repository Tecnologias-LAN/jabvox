require 'rails_helper'
RSpec.describe 'WhatsApp report extended metrics', type: :model do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:ci) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci, assignee: agent) }

  def builder(params = {})
    V2::Reports::WhatsappAgentReportBuilder.new(account: account, params: params)
  end

  it 'logs label apply/remove intervals and aggregates duration', :aggregate_failures do
    conversation.update!(label_list: ['ventas'])
    log = JabvoxConversationLabelLog.find_by(conversation_id: conversation.id, label_jabvox: 'ventas')
    expect(log).to be_present
    expect(log.removed_at_jabvox).to be_nil

    log.update!(applied_at_jabvox: 30.minutes.ago)
    conversation.update!(label_list: [])
    expect(log.reload.removed_at_jabvox).to be_present

    durations = builder.label_durations
    row = durations.find { |r| r[:label] == 'ventas' }
    expect(row).to be_present
    expect(row[:total_seconds]).to be >= 1700 # ~30 min
    expect(row[:occurrences]).to eq(1)
  end

  it 'breaks messages down by media type', :aggregate_failures do
    txt = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'hola')
    img = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    img.attachments.create!(account: account, file_type: :image)

    bd = builder.summary[:incoming_by_type]
    expect(bd[:total]).to eq(2)
    expect(bd[:image]).to eq(1)
    expect(bd[:text]).to eq(1)
  end

  it 'computes time_to_deliver and time_to_read in the summary', :aggregate_failures do
    msg = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent, created_at: 1.hour.ago)
    MessageStatusEvent.create!(account: account, message: msg, status: :delivered, occurred_at: 1.hour.ago + 20)
    MessageStatusEvent.create!(account: account, message: msg, status: :read, occurred_at: 1.hour.ago + 300)

    s = builder.summary
    expect(s[:time_to_deliver][:count]).to eq(1)
    expect(s[:time_to_read][:count]).to eq(1)
    expect(s[:time_to_read][:median]).to be >= 250
  end
end
