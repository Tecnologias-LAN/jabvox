# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Webhooks::Jabvox::Hermes callback' do
  let(:account) { create(:account) }
  let(:secret) { 'super-secret-callback-token' }
  let(:url) { '/webhooks/jabvox/hermes/provisioned' }

  around do |example|
    ClimateControl.modify(HERMES_PROVISIONER_CALLBACK_SECRET: secret) { example.run }
  end

  def auth_headers(token = secret)
    { 'X-Hermes-Provisioner-Token' => token }
  end

  describe 'autenticación' do
    it 'rechaza sin token' do
      post url, params: { account_id: account.id, status: 'ready' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza con token inválido' do
      post url, params: { account_id: account.id, status: 'ready' }, headers: auth_headers('malo')
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'status ready' do
    it 'marca el handoff operativo con URL + token del Hermes de la cuenta' do
      post url,
           params: { account_id: account.id, status: 'ready', hermes_url: 'http://10.147.0.5:8642',
                     hermes_instance_id: 'hermes-acc-1', scoped_token: 'svc-token-xyz',
                     mcp_servers: [{ kind: 'jabvox_core' }] },
           headers: auth_headers
      expect(response).to have_http_status(:ok)

      handoff = account.reload.jabvox_context_forge_handoff
      expect(handoff.status).to eq('ready')
      expect(handoff.hermes_url).to eq('http://10.147.0.5:8642')
      expect(handoff.hermes_operational?).to be(true)
    end
  end

  describe 'status failed' do
    it 'marca el handoff fallido con el error' do
      post url,
           params: { account_id: account.id, status: 'failed', error: 'no arrancó el contenedor' },
           headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(account.reload.jabvox_context_forge_handoff.status).to eq('failed')
    end
  end

  describe 'validaciones' do
    it 'devuelve 404 si la cuenta no existe' do
      post url, params: { account_id: 0, status: 'ready' }, headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'devuelve 422 ante un status desconocido' do
      post url, params: { account_id: account.id, status: 'raro' }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'data sources para el aprovisionador' do
    let(:source) do
      account.jabvox_analytics_data_sources.create!(
        name_jabvox: 'Ventas', engine_jabvox: 'postgresql', host_jabvox: '10.147.0.20',
        port_jabvox: 5432, database_jabvox: 'ventas', username_jabvox: 'ro_user',
        password_jabvox: 's3cr3t', status_jabvox: 'ok'
      )
    end

    context 'cuenta ligada a un aprovisionador' do
      before { allow(JabvoxHermesProvisionerLink).to receive(:active_for?).with(account.id).and_return(true) }

      it 'lista las data sources SIN secretos' do
        source
        get "/webhooks/jabvox/hermes/data_sources/#{account.id}", headers: auth_headers
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['data_sources'].first['name']).to eq('Ventas')
        expect(body.to_s).not_to include('s3cr3t') # nunca la contraseña
      end

      it 'entrega las credenciales COMPLETAS de una data source' do
        get "/webhooks/jabvox/hermes/data_sources/#{account.id}/#{source.id}/credentials",
            headers: auth_headers
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['password']).to eq('s3cr3t') # el aprovisionador SÍ las recibe
        expect(body['host']).to eq('10.147.0.20')
      end

      it 'devuelve 404 si la data source no existe' do
        get "/webhooks/jabvox/hermes/data_sources/#{account.id}/0/credentials", headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'cuenta NO ligada a un aprovisionador' do
      before { allow(JabvoxHermesProvisionerLink).to receive(:active_for?).with(account.id).and_return(false) }

      it 'rechaza el acceso a credenciales con 403' do
        get "/webhooks/jabvox/hermes/data_sources/#{account.id}/#{source.id}/credentials",
            headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'sin token de aprovisionador no entrega credenciales' do
      get "/webhooks/jabvox/hermes/data_sources/#{account.id}/#{source.id}/credentials"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
