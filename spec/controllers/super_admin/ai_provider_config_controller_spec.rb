require 'rails_helper'

# Endpoints de sincronización con el proveedor de IA (LiteLLM): traer todos los teams,
# ligar un team huérfano a una cuenta y desligarlo. Todos exigen super admin.
RSpec.describe 'Super Admin AI Provider Config', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  # El Client cae al MockAdapter cuando el proveedor no está configurado, así que las
  # pruebas no tocan ningún proxy real.
  before { Jabvox::AiProvider::MockAdapter.reset! }

  describe 'sin autenticar' do
    it 'rechaza sincronizar' do
      post '/super_admin/ai_provider_config/sync_provider'
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('sign_in')
    end

    it 'rechaza ligar una cuenta' do
      row = JabvoxAiProviderAccount.create!(team_id_jabvox: 'team-x')
      post '/super_admin/ai_provider_config/link_account',
           params: { provider_account_id: row.id, account_id: account.id }

      expect(response.location).to include('sign_in')
      expect(row.reload).to be_orphan
    end
  end

  context 'when autenticado como super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    describe 'POST sync_provider' do
      it 'exige que el proveedor esté configurado antes de sincronizar' do
        post '/super_admin/ai_provider_config/sync_provider'

        expect(flash[:alert]).to match(/Configura URL, master key/)
      end
    end

    describe 'POST link_account' do
      let!(:orphan) { JabvoxAiProviderAccount.create!(team_id_jabvox: 'team-huerfano', origin_jabvox: 'litellm') }

      it 'liga el team huérfano a la cuenta elegida' do
        post '/super_admin/ai_provider_config/link_account',
             params: { provider_account_id: orphan.id, account_id: account.id }

        expect(orphan.reload.account_id).to eq(account.id)
        expect(flash[:notice]).to match(/ligado a la cuenta/)
      end

      it 'rechaza una cuenta inexistente sin tocar el team' do
        post '/super_admin/ai_provider_config/link_account',
             params: { provider_account_id: orphan.id, account_id: 999_999 }

        expect(orphan.reload).to be_orphan
        expect(flash[:alert]).to match(/No existe la cuenta/)
      end

      it 'rechaza ligar si la cuenta ya tiene otro team' do
        JabvoxAiProviderAccount.create!(account_id: account.id, team_id_jabvox: 'team-existente')

        post '/super_admin/ai_provider_config/link_account',
             params: { provider_account_id: orphan.id, account_id: account.id }

        expect(orphan.reload).to be_orphan
        expect(flash[:alert]).to match(/ya está ligada/)
      end
    end

    describe 'POST unlink_account' do
      it 'desliga sin borrar el team del proveedor' do
        row = JabvoxAiProviderAccount.create!(account_id: account.id, team_id_jabvox: 'team-lig')

        post '/super_admin/ai_provider_config/unlink_account',
             params: { provider_account_id: row.id }

        expect(row.reload).to be_orphan
        expect(row.team_id_jabvox).to eq('team-lig')
      end
    end
  end
end
