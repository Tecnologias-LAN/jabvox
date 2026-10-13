require 'rails_helper'

RSpec.describe 'Campaigns API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }

  describe 'GET /api/v1/accounts/{account.id}/campaigns' do
    let(:inbox) { create(:inbox, account: account) }
    let!(:campaign) do
      create(
        :campaign,
        account: account,
        inbox: inbox,
        trigger_rules: { url: 'https://test.com' }
      )
    end

    it 'still lists campaigns for authorized modules that depend on them' do
      get "/api/v1/accounts/#{account.id}/campaigns",
          headers: headers,
          as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.first[:id]).to eq(campaign.display_id)
    end
  end

  describe 'removed campaign management endpoints' do
    let(:campaign_id) { 1 }

    it 'does not expose campaign details' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign_id}",
          headers: headers,
          as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'does not allow campaign creation' do
      post "/api/v1/accounts/#{account.id}/campaigns",
           params: { title: 'test', message: 'test message' },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'does not allow campaign updates' do
      patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign_id}",
            params: { title: 'test' },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'does not allow campaign deletion' do
      delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign_id}",
             headers: headers,
             as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
