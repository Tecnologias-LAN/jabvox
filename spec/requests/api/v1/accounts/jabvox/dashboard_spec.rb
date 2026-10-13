# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Jabvox account dashboard', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def dashboard_url
    "/api/v1/accounts/#{account.id}/jabvox/dashboard"
  end

  it 'returns message totals and daily data scoped to the authenticated account' do
    inbox = create(:inbox, account: account)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, created_at: Time.zone.parse('2025-03-02 12:00:00'))

    other_account = create(:account)
    other_inbox = create(:inbox, account: other_account)
    other_conversation = create(:conversation, account: other_account, inbox: other_inbox)
    create(:message, account: other_account, inbox: other_inbox, conversation: other_conversation,
                     message_type: :incoming, created_at: Time.zone.parse('2025-03-02 12:00:00'))

    get dashboard_url,
        params: { date_from: '2025-03-02', date_to: '2025-03-02' },
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body.dig('modules', 'messages')).to eq('incoming' => 1, 'outgoing' => 0)
    expect(body.dig('daily', 0)).to include('date' => '2025-03-02', 'messages' => 1)
  end

  it 'rejects datetime filters instead of accepting time-of-day ranges' do
    get dashboard_url,
        params: { date_from: '2025-03-02T08:30:00' },
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to eq('Las fechas deben tener formato AAAA-MM-DD')
  end

  it 'omits enabled modules that a custom role cannot access' do
    account.update!(jabvox_cdr_enabled_jabvox: true)
    role = account.custom_roles.create!(name: 'Dashboard reader', permissions: [])
    account.account_users.find_by(user: agent).update!(custom_role: role)

    get dashboard_url,
        headers: agent.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['modules'].keys).to eq(['messages'])
  end

  it 'returns summaries for each enabled module' do
    account.update!(
      jabvox_cdr_enabled_jabvox: true,
      jabvox_dialer_enabled_jabvox: true,
      jabvox_bulk_whatsapp_enabled_jabvox: true,
      jabvox_tickets_enabled_jabvox: true,
      jabvox_calendar_enabled_jabvox: true,
      jabvox_tasks_enabled_jabvox: true,
      jabvox_kanban_enabled_jabvox: true,
      jabvox_products_enabled_jabvox: true,
      jabvox_sms_enabled_jabvox: true,
      jabvox_email_enabled_jabvox: true,
      jabvox_forms_enabled_jabvox: true
    )

    get dashboard_url,
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['modules'].keys).to match_array(
      %w[messages calls campaigns whatsapp tickets events tasks kanban orders sms email forms]
    )
  end
end
