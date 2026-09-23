require 'rails_helper'

# Endpoints de sincronización con el proveedor de IA (LiteLLM): traer todos los teams,
# ligar un team huérfano a una cuenta y desligarlo. Todos exigen super admin.
RSpec.describe 'Super Admin AI Provider Config', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  # El Client cae al MockAdapter cuando el proveedor no está configurado, así que las
  # pruebas no tocan ningún proxy real.
  before { Jabvox::AiProvider::MockAdapter.reset! }

  describe 'seguridad de endpoints' do
    let!(:row) { JabvoxAiProviderAccount.create!(team_id_jabvox: 'team-sec') }

    # Todas las acciones de escritura viven tras authenticate_super_admin!. Sin sesión deben
    # redirigir a login y NO ejecutar nada.
    it 'rechaza set_team_models sin sesión de super admin' do
      post '/super_admin/ai_provider_config/set_team_models',
           params: { provider_account_id: row.id, models: ['x'] }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('sign_in')
      expect(row.reload.remote_models_jabvox).to eq([])
    end

    it 'rechaza el diagnóstico de un team sin sesión de super admin' do
      get '/super_admin/ai_provider_config', params: { tab: 'accounts', inspect_team: 'team-sec' }

      expect(response.location).to include('sign_in')
    end
  end

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

    describe 'POST set_team_models' do
      let!(:row) { JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: 'team-mod') }

      before { Jabvox::AiProvider::MockAdapter.instance.seed_team(team_id: 'team-mod') }

      it 'rechaza un modelo que el proveedor no expone' do
        post '/super_admin/ai_provider_config/set_team_models',
             params: { provider_account_id: row.id, models: ['modelo-inventado'] }

        expect(flash[:alert]).to match(/no expone estos modelos/)
        expect(row.reload.remote_models_jabvox).to eq([])
      end

      it 'asigna un modelo válido del catálogo' do
        post '/super_admin/ai_provider_config/set_team_models',
             params: { provider_account_id: row.id, models: ['mock/model-a'] }

        expect(flash[:notice]).to match(%r{acceso a mock/model-a})
        expect(row.reload.remote_models_jabvox).to eq(['mock/model-a'])
      end

      it 'sin selección deja el team con acceso a todos' do
        post '/super_admin/ai_provider_config/set_team_models',
             params: { provider_account_id: row.id, models: [] }

        expect(flash[:notice]).to match(/todos los modelos/)
        expect(row.reload.remote_models_jabvox).to eq([])
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
