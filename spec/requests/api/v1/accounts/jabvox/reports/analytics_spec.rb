# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Jabvox reports analytics drill-down', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  def base = "/api/v1/accounts/#{account.id}/jabvox/reports/analytics"

  before do
    2.times do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, sender: agent, status: :sent, created_at: 2.days.ago)
    end
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, sender: agent, status: :failed, created_at: 2.days.ago)
  end

  describe 'GET /:metric_key/records' do
    it 'returns paginated rows filtered by agent' do
      get "#{base}/messages_sent/records", params: { agent_ids: [agent.id] },
                                           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['data']).to be_an(Array)
      expect(body['meta']).to include('total_count', 'has_more')
    end

    it 'defaults messages to successful statuses (matches the agents cell)' do
      get "#{base}/messages_sent/records", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['meta']['total_count']).to eq(2) # 2 sent, failed excluded
    end

    it 'filters messages by status=failed' do
      get "#{base}/messages_sent/records", params: { status: ['failed'] },
                                           headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['meta']['total_count']).to eq(1)
    end

    it 'returns 422 when the range exceeds the hard limit' do
      get "#{base}/messages_sent/records", params: { preset: 'custom', from: '2020-01-01', to: '2026-12-31' },
                                           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'denies an agent without the reports permission' do
      get "#{base}/messages_sent/records", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for an unknown metric' do
      get "#{base}/not_a_metric/records", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /:metric_key/breakdown' do
    it 'returns totals broken down by message status, respecting filters' do
      get "#{base}/messages_sent/breakdown", params: { status: %w[sent failed] },
                                             headers: admin.create_new_auth_token, as: :json
      body = response.parsed_body
      expect(response).to have_http_status(:success)
      expect(body['total']).to eq(3) # 2 sent + 1 failed
      labels = body['rows'].map { |r| r['label'] }
      expect(labels).to include('Enviado', 'Fallido')
    end

    it 'exposes the metric filter config' do
      get "#{base}/messages_sent/breakdown", headers: admin.create_new_auth_token, as: :json
      keys = response.parsed_body['filters_config'].map { |f| f['key'] }
      expect(keys).to include('status')
    end

    # Regression: a gestión with several answer rows (one per form question)
    # must count as ONE management, not one per answer.
    it 'counts one management per note even with multiple answer rows' do
      state = account.jabvox_management_states.create!(name_jabvox: 'Interesado', created_by_id: agent.id)
      note = create(:message, account: account, inbox: inbox, conversation: conversation,
                              message_type: :outgoing, private: true, sender: agent, created_at: 2.days.ago)
      3.times do |i|
        JabvoxManagementAnswer.create!(account_id: account.id, message_id: note.id,
                                       jabvox_management_state_id: state.id,
                                       created_by_id: agent.id, label: "P#{i}", value: "R#{i}",
                                       created_at: 2.days.ago)
      end
      get "#{base}/managements/records", params: { agent_ids: [agent.id] },
                                         headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['meta']['total_count']).to eq(1)

      get "#{base}/managements/breakdown", params: { agent_ids: [agent.id] },
                                           headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['total']).to eq(1)
    end
  end
end
