require 'rails_helper'
RSpec.describe 'WhatsApp Groups endpoints', type: :request do
  let(:account) { create(:account, jabvox_whatsapp_groups_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  def base = "/api/v1/accounts/#{account.id}/jabvox/whatsapp_groups"

  it 'reports ineligibility with a reason (no OBA)' do
    get "#{base}/inboxes/#{inbox.id}/eligibility", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['eligible']).to be false
    expect(body['reason']).to eq('not_official_business')
    expect(body['feature_enabled']).to be true
  end

  it 'blocks group creation on an ineligible inbox' do
    post "#{base}/groups", params: { group: { name: 'Sala', inbox_id: inbox.id } },
                           headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['reason']).to eq('not_official_business')
  end

  it 'lists groups (empty) for an enabled account' do
    get "#{base}/groups", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to eq([])
  end

  it '403s when the feature is disabled' do
    account.update!(jabvox_whatsapp_groups_enabled_jabvox: false)
    get "#{base}/groups", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
