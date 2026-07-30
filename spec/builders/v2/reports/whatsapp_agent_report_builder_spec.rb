# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V2::Reports::WhatsappAgentReportBuilder do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:agent_a) { create(:user, account: account, role: :administrator) }
  let(:agent_b) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '573001112233') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          contact_inbox: contact_inbox, assignee: agent_a)
  end

  let(:params) { { from: 2.hours.ago.to_i.to_s, to: 5.minutes.from_now.to_i.to_s } }
  subject(:builder) { described_class.new(account: account, params: params) }

  # inbound → agent_b replies (read) → inbound again (unanswered)
  def build_timeline!
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, content: 'Hola', created_at: 30.minutes.ago)
    reply = create(:message, account: account, inbox: inbox, conversation: conversation,
                             message_type: :outgoing, sender: agent_b, status: :read,
                             content: 'Buenas', created_at: 28.minutes.ago)
    MessageStatusEvent.create!(message: reply, account_id: account.id, conversation_id: conversation.id,
                               inbox_id: inbox.id, status: :delivered, occurred_at: 27.minutes.ago)
    MessageStatusEvent.create!(message: reply, account_id: account.id, conversation_id: conversation.id,
                               inbox_id: inbox.id, status: :read, occurred_at: 25.minutes.ago)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, content: '¿Sigue?', created_at: 10.minutes.ago)
    account.reporting_events.create!(name: 'first_response', value: 120, value_in_business_hours: 120,
                                     conversation_id: conversation.id, inbox_id: inbox.id,
                                     user_id: agent_b.id, account_id: account.id,
                                     event_start_time: 30.minutes.ago, event_end_time: 28.minutes.ago)
    reply
  end

  describe '#summary' do
    before { build_timeline! }

    it 'counts sent/delivered/read and builds the funnel' do
      s = builder.summary
      expect(s[:sent]).to eq(1)
      expect(s[:delivered]).to eq(1)
      expect(s[:read]).to eq(1)
      expect(s[:received]).to eq(2)
      expect(s[:read_rate]).to eq(100.0)
      expect(s[:funnel].map { |f| f[:step] }).to eq(%w[sent delivered read responded resolved])
    end
  end

  describe '#agents' do
    before { build_timeline! }

    it 'attributes messages/read/times to the replying agent (agent_b)' do
      row = builder.agents.find { |r| r[:id] == agent_b.id }
      expect(row[:sent]).to eq(1)
      expect(row[:read]).to eq(1)
      expect(row[:first_response][:median]).to eq(120)
      expect(row[:time_to_read][:count]).to eq(1)
    end

    it 'flags the assigned agent that never replied as no_reply' do
      row = builder.agents.find { |r| r[:id] == agent_a.id }
      expect(row[:conversations_assigned]).to eq(1)
      expect(row[:no_reply]).to eq(1)
    end
  end

  describe '#conversation_timeline (multi-agente)' do
    before { build_timeline! }

    it 'reconstructs turns: one answered by agent_b, one unanswered' do
      tl = builder.conversation_timeline(conversation.id)
      expect(tl[:turns].size).to eq(2)
      expect(tl[:turns][0][:status]).to eq('answered')
      expect(tl[:turns][0][:responder_id]).to eq(agent_b.id)
      expect(tl[:turns][0][:response_seconds]).to be_a(Numeric)
      expect(tl[:turns][1][:status]).to eq('unanswered')
      expect(tl[:turns][1][:responder_id]).to be_nil
    end
  end

  describe '#rankings' do
    before { build_timeline! }

    it 'ranks agents by first_response (asc = fastest first)' do
      ranking = builder.rankings(metric: 'first_response', order: 'asc')
      expect(ranking.first[:id]).to eq(agent_b.id)
      expect(ranking.first[:value]).to eq(120)
    end
  end

  describe 'time_stats (median/avg/p90)' do
    it 'computes median, average and p90 over a value set' do
      stats = builder.send(:time_stats, [10, 20, 30, 40, 100])
      expect(stats[:median]).to eq(30)
      expect(stats[:avg]).to eq(40)
      expect(stats[:count]).to eq(5)
      expect(stats[:p90]).to be >= 40
    end

    it 'returns nils for an empty set' do
      expect(builder.send(:time_stats, [])).to eq({ avg: nil, median: nil, p90: nil, count: 0 })
    end
  end
end
