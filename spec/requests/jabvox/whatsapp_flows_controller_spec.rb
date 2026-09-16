require 'rails_helper'

RSpec.describe 'Jabvox WhatsApp Flows API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  let(:other_account) { create(:account) }
  let(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:other_channel) { create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:other_inbox) { create(:inbox, account: other_account, channel: other_channel) }

  def base_url(account_id)
    "/api/v1/accounts/#{account_id}/jabvox/whatsapp_flows"
  end

  describe 'GET /categories' do
    it 'returns the fixed Meta category catalog' do
      get "#{base_url(account.id)}/categories", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['categories']).to match_array(JabvoxWhatsappFlow::CATEGORIES)
    end
  end

  describe 'POST / (create)' do
    it 'creates a flow scoped to the current account' do
      post base_url(account.id), params: { name: 'Encuesta', category: 'SURVEY', inbox_id: inbox.id }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      expect(JabvoxWhatsappFlow.last.account_id).to eq(account.id)
    end
  end

  describe 'account isolation' do
    let!(:flow_a) { create(:jabvox_whatsapp_flow, account: account, inbox: inbox, name: 'Flow de cuenta A') }

    it 'account B cannot see account A flow via index' do
      get base_url(other_account.id), headers: other_admin.create_new_auth_token, as: :json
      expect(response.parsed_body['flows']).to be_empty
    end

    it 'account B gets a 404 (not a leak) trying to show account A flow by id' do
      get "#{base_url(other_account.id)}/#{flow_a.id}", headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'account B cannot update account A flow' do
      patch "#{base_url(other_account.id)}/#{flow_a.id}", params: { name: 'Hackeado' }, headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(flow_a.reload.name).to eq('Flow de cuenta A')
    end

    it 'account B cannot publish account A flow' do
      post "#{base_url(other_account.id)}/#{flow_a.id}/publish", headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'account B cannot destroy account A flow' do
      expect do
        delete "#{base_url(other_account.id)}/#{flow_a.id}", headers: other_admin.create_new_auth_token, as: :json
      end.not_to change(JabvoxWhatsappFlow, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'account A itself can see and edit its own flow' do
      get "#{base_url(account.id)}/#{flow_a.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(flow_a.id)
    end
  end

  describe 'PATCH /:id (update)' do
    let!(:flow) { create(:jabvox_whatsapp_flow, account: account, inbox: inbox) }

    it 'updates a draft flow' do
      patch "#{base_url(account.id)}/#{flow.id}", params: { name: 'Nuevo nombre' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(flow.reload.name).to eq('Nuevo nombre')
    end

    it 'refuses to update a flow already published on Meta' do
      flow.update!(meta_status: 'PUBLISHED')
      patch "#{base_url(account.id)}/#{flow.id}", params: { name: 'Nuevo nombre' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flow.reload.name).not_to eq('Nuevo nombre')
    end
  end

  describe 'POST /:id/duplicate' do
    let!(:flow) { create(:jabvox_whatsapp_flow, :published, account: account, inbox: inbox) }

    it 'creates a fresh draft copy without meta_flow_id/meta_status' do
      post "#{base_url(account.id)}/#{flow.id}/duplicate", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      dup = JabvoxWhatsappFlow.find(response.parsed_body['id'])
      expect(dup.status).to eq('draft')
      expect(dup.meta_flow_id).to be_nil
      expect(dup.screens_json).to eq(flow.screens_json)
    end
  end

  describe 'POST /:id/validate' do
    let!(:flow) { create(:jabvox_whatsapp_flow, account: account, inbox: inbox) }

    it 'runs the Validator and persists validation_errors_json' do
      post "#{base_url(account.id)}/#{flow.id}/validate", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['valid']).to be(true)
    end
  end

  describe 'authorization' do
    let!(:flow) { create(:jabvox_whatsapp_flow, account: account, inbox: inbox) }
    let(:agent) { create(:user, account: account, role: :agent) }

    it 'a plain agent without the jabvox_whatsapp_flows_manage permission is forbidden' do
      get base_url(account.id), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'a custom-role agent granted jabvox_whatsapp_flows_manage is allowed' do
      role = create(:custom_role, account: account, permissions: ['jabvox_whatsapp_flows_manage'])
      account_user = AccountUser.find_by(account: account, user: agent)
      account_user.update!(custom_role: role)

      get base_url(account.id), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /:id/submissions' do
    let!(:flow) { create(:jabvox_whatsapp_flow, account: account, inbox: inbox) }
    let(:contact) { create(:contact, account: account) }

    it 'lists submissions for the flow' do
      create(:jabvox_whatsapp_flow_submission, account: account, jabvox_whatsapp_flow: flow, contact: contact)
      get "#{base_url(account.id)}/#{flow.id}/submissions", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['total']).to eq(1)
    end
  end
end
