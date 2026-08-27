# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Webhooks::Jabvox::HermesAgent (agente ejecuta tools)' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) do
    JabvoxHermesAgent.create!(account: account, user: user, name_jabvox: 'Agente', status_jabvox: 'active')
  end

  before do
    JabvoxHermesUserPermission.create!(account: account, user: user, permissions_jabvox: %w[read create])
  end

  def agent_headers(token = agent.agent_token_jabvox)
    { 'X-Hermes-Agent-Token' => token }
  end

  describe 'autenticación por token de agente' do
    it 'rechaza sin token' do
      get '/webhooks/jabvox/hermes_agent/tools'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza con token inválido' do
      get '/webhooks/jabvox/hermes_agent/tools', headers: agent_headers('malo')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'acepta Bearer con el token del agente' do
      get '/webhooks/jabvox/hermes_agent/tools',
          headers: { 'Authorization' => "Bearer #{agent.agent_token_jabvox}" }
      expect(response).to have_http_status(:ok)
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
