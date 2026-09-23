# frozen_string_literal: true

require 'rails_helper'

# Varias cuentas conectadas al mismo proveedor: lo que le pase a una no debe afectar al
# resto. Antes, un proveedor lento bloqueaba el worker durante minutos por cada request, así
# que una sola cuenta con el proxy caído podía agotar los workers y tumbar a las demás.
RSpec.describe 'Saldo IA — aislamiento entre cuentas', type: :request do
  let(:mock) { Jabvox::AiProvider::MockAdapter.new }

  def account_with_team(team_id)
    account = create(:account, jabvox_ai_chat_enabled_jabvox: true)
    JabvoxAiProviderAccount.create!(account: account, team_id_jabvox: team_id)
    mock.seed_team(team_id: team_id)
    [account, create(:user, account: account, role: :administrator)]
  end

  before { Jabvox::AiProvider::Client.adapter_override = mock }

  after { Jabvox::AiProvider::Client.adapter_override = nil }

  it 'cada cuenta ve solo las keys de su propio team' do
    cuenta_a, admin_a = account_with_team('team-a')
    _cuenta_b, _admin_b = account_with_team('team-b')

    Jabvox::AiProvider::Client.new.generate_key(team_id: 'team-a', key_alias: 'de-a')
    Jabvox::AiProvider::Client.new.generate_key(team_id: 'team-b', key_alias: 'de-b')

    get "/api/v1/accounts/#{cuenta_a.id}/jabvox/ai_budget/keys",
        headers: admin_a.create_new_auth_token, as: :json

    aliases = response.parsed_body['keys'].map { |k| k['alias'] }
    expect(aliases).to include('de-a')
    expect(aliases).not_to include('de-b')
  end

  it 'el admin de una cuenta no puede leer el saldo de otra' do
    cuenta_a, _admin_a = account_with_team('team-a')
    _cuenta_b, admin_b = account_with_team('team-b')

    # admin_b pide la ruta de la cuenta A: no pertenece a ella.
    get "/api/v1/accounts/#{cuenta_a.id}/jabvox/ai_budget",
        headers: admin_b.create_new_auth_token, as: :json

    expect(response).not_to have_http_status(:success)
  end

  it 'un agente (no admin) no accede aunque pertenezca a la cuenta' do
    cuenta_a, = account_with_team('team-a')
    agente = create(:user, account: cuenta_a, role: :agent)

    get "/api/v1/accounts/#{cuenta_a.id}/jabvox/ai_budget",
        headers: agente.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'si el proveedor falla para una cuenta, otra cuenta sigue respondiendo' do
    cuenta_a, admin_a = account_with_team('team-a')
    cuenta_b, admin_b = account_with_team('team-b')

    # El proveedor falla SOLO al listar las keys del team A.
    allow(mock).to receive(:request).and_wrap_original do |original, method, path, **kwargs|
      args = (kwargs[:body] || kwargs[:params] || {}).transform_keys(&:to_s)
      if path == '/key/list' && args['team_id'] == 'team-a'
        { status: 503, body: nil, body_text: 'unavailable' }
      else
        original.call(method, path, **kwargs)
      end
    end

    get "/api/v1/accounts/#{cuenta_a.id}/jabvox/ai_budget/keys",
        headers: admin_a.create_new_auth_token, as: :json
    expect(response).to have_http_status(:bad_gateway)

    # La cuenta B no se ve arrastrada por el fallo de A.
    get "/api/v1/accounts/#{cuenta_b.id}/jabvox/ai_budget/keys",
        headers: admin_b.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'el saldo sigue visible aunque el proveedor no responda (usa el gasto cacheado)' do
    cuenta, admin = account_with_team('team-slow')
    JabvoxAiProviderAccount.find_by(account_id: cuenta.id)
                           .update!(purchased_budget_cents_jabvox: 2_000, cached_spend_jabvox: 3.0)
    allow(mock).to receive(:request).and_return({ status: 503, body: nil, body_text: 'down' })

    get "/api/v1/accounts/#{cuenta.id}/jabvox/ai_budget",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['total_budget_usd'].to_f).to eq(20.0)
    expect(response.parsed_body['cached_spend_usd'].to_f).to eq(3.0)
  end
end
