require 'rails_helper'
RSpec.describe 'WhatsApp Groups report', type: :request do
  let(:account) { create(:account, jabvox_whatsapp_groups_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:g1) { JabvoxWhatsappGroup.create!(account: account, inbox: inbox, name_jabvox: 'A', status_jabvox: 'active') }

  before do
    g1
    JabvoxWhatsappGroup.create!(account: account, inbox: inbox, name_jabvox: 'B', status_jabvox: 'archived')
    3.times { |i| g1.members.create!(account: account, phone_number_jabvox: "57300111220#{i}", invite_status_jabvox: 'joined') }
  end

  it 'returns groups summary' do
    get "/api/v2/accounts/#{account.id}/reports/whatsapp_groups/summary", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    b = response.parsed_body
    expect(b['total_groups']).to eq(2)
    expect(b['active_groups']).to eq(1)
    expect(b['archived_groups']).to eq(1)
    expect(b['total_members']).to eq(3)
  end

  it 'returns groups list' do
    get "/api/v2/accounts/#{account.id}/reports/whatsapp_groups/list", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.size).to eq(2)
  end
end
