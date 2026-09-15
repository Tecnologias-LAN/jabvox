# frozen_string_literal: true

require 'rails_helper'

# El dashboard decidía "aprovisionado" leyendo `connected`, un campo que el backend NUNCA
# enviaba cuando la cuenta SÍ tenía team: `summary` no lo incluía y solo aparecía en la
# respuesta vacía. Resultado: una cuenta con team ligado seguía viendo "no aprovisionado".
# Además, un team importado sin tope en el proveedor (max_budget null) se mostraba como
# $0.00 —que significa lo contrario, agotado— y bloqueaba la creación de keys.
RSpec.describe 'Api::V1::Accounts::Jabvox::AiBudget', type: :request do
  let(:account) { create(:account, jabvox_ai_chat_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:mock) { Jabvox::AiProvider::MockAdapter.new }

  before do
    # Fuerza el adaptador mock en todas las instancias del Client que crea el controller.
    Jabvox::AiProvider::Client.adapter_override = mock
  end

  after { Jabvox::AiProvider::Client.adapter_override = nil }

  def show_balance(user: admin)
    get "/api/v1/accounts/#{account.id}/jabvox/ai_budget",
        headers: user.create_new_auth_token, as: :json
  end

  describe 'GET show' do
    it 'reporta connected: true cuando la cuenta tiene team en el proveedor' do
      JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: 'team-1',
                                      plan_budget_cents_jabvox: 500)

      show_balance

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['connected']).to be true
    end

    it 'reporta connected: false cuando la cuenta no tiene team' do
      show_balance

      expect(response.parsed_body['connected']).to be false
    end

    it 'marca como ilimitado el team sin tope y no devuelve un restante negativo' do
      # Team importado de LiteLLM: sin max_budget remoto, sin saldo local, con gasto real.
      JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: 'team-ilim',
                                      origin_jabvox: 'litellm',
                                      remote_max_budget_jabvox: nil)
      # El gasto se lee del proveedor en cada `show` (refresh_spend!), así que la fuente de
      # verdad del test es el mock, no la fila en BD.
      mock.seed_team(team_id: 'team-ilim', spend: 6.22)

      show_balance
      body = response.parsed_body

      expect(body['connected']).to be true
      expect(body['unlimited']).to be true
      # Sin esto, la UI mostraba "-6.22" como si el saldo estuviera sobregirado.
      expect(body['remaining_usd']).to be_nil
      # El gasto real se conserva tal cual.
      expect(body['cached_spend_usd'].to_f).to be > 0
    end

    it 'sigue calculando el restante cuando el team SÍ tiene tope' do
      JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: 'team-cap',
                                      purchased_budget_cents_jabvox: 2_000)
      mock.seed_team(team_id: 'team-cap', spend: 5.0)

      show_balance

      expect(response.parsed_body['unlimited']).to be false
      expect(response.parsed_body['remaining_usd'].to_f).to eq(15.0)
    end

    it 'rechaza a un agente (solo administradores)' do
      show_balance(user: agent)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST create_key' do
    def create_key(params, user: admin)
      post "/api/v1/accounts/#{account.id}/jabvox/ai_budget/create_key",
           params: params, headers: user.create_new_auth_token, as: :json
    end

    it 'permite crear key con tope en un team ILIMITADO (antes lo rechazaba por comparar contra 0)' do
      JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: 'team-ilim',
                                      remote_max_budget_jabvox: nil)
      mock.seed_team(team_id: 'team-ilim')

      create_key({ key_alias: 'produccion', max_budget_usd: 50 })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['key']).to be_present
    end

    it 'sigue rechazando una key que excede el tope de un team CON saldo' do
      JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: 'team-cap',
                                      purchased_budget_cents_jabvox: 1_000)
      mock.seed_team(team_id: 'team-cap')

      create_key({ max_budget_usd: 99 })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/excede el saldo/)
    end

    it 'rechaza un tope negativo o cero' do
      JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: 'team-x')
      mock.seed_team(team_id: 'team-x')

      create_key({ max_budget_usd: -5 })

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'gestión de keys — aislamiento entre cuentas' do
    let(:otra_cuenta) { create(:account, jabvox_ai_chat_enabled_jabvox: true) }

    before do
      JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: 'team-propio')
      JabvoxAiProviderAccount.create!(account: otra_cuenta, team_id_jabvox: 'team-ajeno')
      mock.seed_team(team_id: 'team-propio')
      mock.seed_team(team_id: 'team-ajeno')
    end

    def key_of(team_id, alias_name)
      resp = Jabvox::AiProvider::Client.new.generate_key(team_id: team_id, key_alias: alias_name)
      resp.data['token_id']
    end

    def block(token, user: admin)
      post "/api/v1/accounts/#{account.id}/jabvox/ai_budget/block_key",
           params: { token_id: token }, headers: user.create_new_auth_token, as: :json
    end

    it 'bloquea una key propia' do
      token = key_of('team-propio', 'mia')

      block(token)

      expect(response).to have_http_status(:success)
    end

    it 'NO permite bloquear la key de otra cuenta aunque se conozca su token' do
      ajena = key_of('team-ajeno', 'ajena')

      block(ajena)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to match(/no pertenece a esta cuenta/)
    end

    it 'rechaza un token vacío' do
      block('')

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rechaza a un agente' do
      token = key_of('team-propio', 'mia')

      block(token, user: agent)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
