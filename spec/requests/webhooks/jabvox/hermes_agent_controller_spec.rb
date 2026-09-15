# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Webhooks::Jabvox::HermesAgent (agente ejecuta tools)' do
  let(:account) { create(:account) }
  # Admin: su rol concede capacidad de gestión, requisito del cruce de permisos de rol.
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    JabvoxHermesAgent.create!(account: account, user: user, name_jabvox: 'Agente', status_jabvox: 'active')
  end

  # Las tools se ejecutan por el token de CONEXIÓN, que además declara desde qué IPs acepta
  # ejecutar (ver JabvoxHermesConnection#ip_allowed?). ALLOWED_IP es la IP del Hermes.
  let(:allowed_ip) { '203.0.113.5' }
  let(:connection) do
    conn = JabvoxHermesConnection.create!(
      account: account,
      name_jabvox: 'hermes-uno',
      hermes_agent_name_jabvox: 'hermes-uno',
      base_url_jabvox: 'https://hermes.example.com',
      allowed_ips_jabvox: [allowed_ip]
    )
    JabvoxHermesAgentConnection.create!(hermes_connection: conn, hermes_agent: agent)
    conn
  end

  before do
    JabvoxHermesUserPermission.create!(account: account, user: user, permissions_jabvox: %w[read create])
  end

  def agent_headers(token = connection.reload.action_token_jabvox, ip: allowed_ip)
    { 'X-Hermes-Agent-Token' => token, 'REMOTE_ADDR' => ip }
  end

  describe 'autenticación por token' do
    it 'rechaza sin token' do
      get '/webhooks/jabvox/hermes_agent/tools'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza con token inválido' do
      get '/webhooks/jabvox/hermes_agent/tools', headers: agent_headers('malo')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'acepta Bearer con el token de la conexión desde su IP' do
      get '/webhooks/jabvox/hermes_agent/tools',
          headers: { 'Authorization' => "Bearer #{connection.reload.action_token_jabvox}",
                     'REMOTE_ADDR' => allowed_ip }
      expect(response).to have_http_status(:ok)
    end
  end

  # El token dice QUIÉN llama; la allowlist verifica que la llamada venga del propio Hermes.
  describe 'restricción por IP de origen' do
    it 'rechaza un token válido usado desde otra IP' do
      get '/webhooks/jabvox/hermes_agent/tools', headers: agent_headers(ip: '45.77.167.167')
      expect(response).to have_http_status(:forbidden)
    end

    it 'rechaza si la conexión no declaró ninguna IP (fail-closed)' do
      connection.update!(allowed_ips_jabvox: [])
      get '/webhooks/jabvox/hermes_agent/tools', headers: agent_headers
      expect(response).to have_http_status(:forbidden)
    end

    # El esquema antiguo de token-de-agente no tiene allowlist: dejarlo ejecutar sería una
    # puerta trasera que anula la restricción por IP.
    it 'rechaza el token de agente antiguo, que no tiene allowlist' do
      get '/webhooks/jabvox/hermes_agent/tools',
          headers: { 'X-Hermes-Agent-Token' => agent.agent_token_jabvox, 'REMOTE_ADDR' => allowed_ip }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET tools' do
    it 'lista solo las tools permitidas del agente' do
      get '/webhooks/jabvox/hermes_agent/tools', headers: agent_headers
      body = response.parsed_body
      expect(body['tools']).to include('get_labels', 'create_label')
      expect(body['tools']).not_to include('update_label') # no tiene permiso write
    end
  end

  describe 'POST execute' do
    it 'ejecuta create_label con los permisos del agente' do
      post '/webhooks/jabvox/hermes_agent/execute',
           params: { tool: 'create_label', args: { title: 'hermes' } }, headers: agent_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to be(true)
    end

    it 'rechaza una tool sin permiso (403)' do
      post '/webhooks/jabvox/hermes_agent/execute',
           params: { tool: 'update_label', args: { id: 1, title: 'x' } }, headers: agent_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'NUNCA puede borrar (delete no existe → forbidden)' do
      post '/webhooks/jabvox/hermes_agent/execute',
           params: { tool: 'delete_label', args: { id: 1 } }, headers: agent_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'un agente desactivado no puede ejecutar' do
      agent.update!(status_jabvox: 'disabled')
      post '/webhooks/jabvox/hermes_agent/execute',
           params: { tool: 'create_label', args: { title: 'x' } }, headers: agent_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
