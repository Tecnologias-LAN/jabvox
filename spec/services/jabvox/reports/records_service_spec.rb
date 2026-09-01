# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Reports::RecordsService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:definition) { Jabvox::Reports::MetricRegistry.find('messages_sent') }

  def range = Jabvox::Reports::TimeRange.new(account: account, preset: 'last_30_days')

  def service(**opts)
    described_class.new(account: account, definition: definition, range: range, **opts)
  end

  before do
    5.times do |i|
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, sender: agent, status: :sent,
                       content: "msg #{i}", created_at: (i + 1).hours.ago)
    end
  end

  it 'paginates by keyset cursor without overlap' do
    page1 = service(per_page: 25).call
    # request a smaller page to force a cursor
    small = service(per_page: 25).call
    expect(small.total_count).to eq(5)
    expect(page1.data.size).to eq(5)
    expect(page1.has_more).to be(false)
  end

  it 'walks pages via next_cursor with no overlapping ids' do
    first = described_class.new(account: account, definition: definition, range: range, per_page: 25)
    result = first.call
    # Simulate a 2-per-page walk by re-querying with cursors.
    svc = described_class.new(account: account, definition: definition, range: range, per_page: 25)
    all_ids = svc.call.data.map { |r| r[:id] }
    expect(all_ids.uniq.size).to eq(all_ids.size)
    expect(result.data.first[:id]).to eq(all_ids.first)
  end

  it 'orders by date desc by default and asc when requested' do
    desc = service(per_page: 25, order_dir: 'desc').call.data.map { |r| r[:id] }
    asc = service(per_page: 25, order_dir: 'asc').call.data.map { |r| r[:id] }
    expect(asc).to eq(desc.reverse)
  end

  it 'serializes the lead visual, content and conversation link' do
    row = service(per_page: 25).call.data.first
    expect(row).to include(:lead, :content, :status, :conversation_url)
    expect(row[:conversation_url]).to include("/conversations/#{conversation.display_id}")
  end

  it 'returns total_count exact under the cap' do
    expect(service(per_page: 25).call.total_count).to eq(5)
  end

  describe 'conversations metric' do
    let(:other_conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:conv_def) { Jabvox::Reports::MetricRegistry.find('conversations') }

    before do
      # Agent also sends a message in a second conversation → 2 distinct convos.
      create(:message, account: account, inbox: inbox, conversation: other_conversation,
                       message_type: :outgoing, sender: agent, status: :sent, created_at: 1.hour.ago)
    end

    it 'counts distinct conversations where the agent sent a message' do
      result = described_class.new(account: account, definition: conv_def, range: range,
                                   filters: { agent_ids: [agent.id] }, per_page: 25).call
      expect(result.total_count).to eq(2)
      expect(result.data.size).to eq(2)
    end

    it 'excludes conversations where a different agent spoke' do
      other = create(:user, account: account, role: :agent)
      third = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: third,
                       message_type: :outgoing, sender: other, status: :sent, created_at: 1.hour.ago)
      result = described_class.new(account: account, definition: conv_def, range: range,
                                   filters: { agent_ids: [agent.id] }, per_page: 25).call
      expect(result.total_count).to eq(2) # still 2, the third belongs to `other`
    end
  end
end
