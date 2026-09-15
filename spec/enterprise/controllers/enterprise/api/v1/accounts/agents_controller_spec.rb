require 'rails_helper'

RSpec.describe 'Enterprise Agents API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:custom_role) { create(:custom_role, account: account) }

  describe 'POST /api/v1/accounts/{account.id}/agents' do
    let(:params) { { email: 'test@example.com', name: 'Test User', role: 'agent', custom_role_id: custom_role.id } }

    context 'when it is an authenticated administrator' do
      it 'creates an agent with the specified custom role' do
        post "/api/v1/accounts/#{account.id}/agents", headers: admin.create_new_auth_token, params: params, as: :json

        expect(response).to have_http_status(:success)
        agent = account.agents.last
        expect(agent.account_users.first.custom_role_id).to eq(custom_role.id)
        expect(JSON.parse(response.body)['custom_role_id']).to eq(custom_role.id)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/agents/:id' do
    let(:other_agent) { create(:user, account: account, role: :agent) }

    context 'when it is an authenticated administrator' do
      it 'modified the custom role of the agent' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            headers: admin.create_new_auth_token,
            params: { custom_role_id: custom_role.id },
            as: :json

        expect(response).to have_http_status(:success)
        expect(other_agent.account_users.first.reload.custom_role_id).to eq(custom_role.id)
        expect(JSON.parse(response.body)['custom_role_id']).to eq(custom_role.id)
      end
    end

    # Seguridad: JabvoxPermissions concede TODO a un administrator? sin mirar el custom
    # role. Sin este downgrade, asignarle un rol personalizado a alguien que YA era
    # administrator lo dejaba con acceso total ADEMÁS del rol — el rol quedaba sin
    # ningún efecto real (el usuario seguía pudiendo hacer todo lo de admin).
    context 'when assigning a custom role to an existing administrator' do
      let(:restricted_role) { create(:custom_role, account: account, permissions: []) }
      let(:existing_admin) { create(:user, account: account, role: :administrator) }

      it 'downgrades the base role to agent, so the custom role is the only source of permissions' do
        put "/api/v1/accounts/#{account.id}/agents/#{existing_admin.id}",
            headers: admin.create_new_auth_token,
            params: { custom_role_id: restricted_role.id },
            as: :json

        expect(response).to have_http_status(:success)
        account_user = existing_admin.account_users.first.reload
        expect(account_user.custom_role_id).to eq(restricted_role.id)
        expect(account_user).to be_agent
        expect(JabvoxPermissions.user_grants_permission?(account_user, 'jabvox_sms_manage')).to be false
      end

      it 'does NOT downgrade when custom_role_id is explicitly cleared (unassigning keeps administrator)' do
        existing_admin.account_users.first.update!(custom_role_id: restricted_role.id, role: :agent)

        put "/api/v1/accounts/#{account.id}/agents/#{existing_admin.id}",
            headers: admin.create_new_auth_token,
            params: { custom_role_id: nil },
            as: :json

        expect(response).to have_http_status(:success)
        expect(existing_admin.account_users.first.reload.custom_role_id).to be_nil
      end
    end
  end
end
