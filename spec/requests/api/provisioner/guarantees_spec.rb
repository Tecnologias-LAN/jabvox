# frozen_string_literal: true

require 'rails_helper'

# Verificación de las 3 garantías pedidas:
#   1. Una IP específica en la allowlist permite SOLO esa IP.
#   2. Sin token (o con token inválido) la API no devuelve NADA: ni datos, ni catálogo de tools.
#   3. Con token, solo las tools de los permisos que tenga.
RSpec.describe 'Verificación API Provisioner', type: :request do
  let!(:generated) do
    JabvoxProvisionerApiToken.generate!(
      created_by_id: nil,
      allowed_ips: ['10.147.100.5'], # UNA IP específica, no un rango
      permissions: { 'accounts' => %w[view] }
    )
  end
  let(:plaintext) { generated[1] }
  let(:signing_secret) { generated[2] }

  def headers_for(body, token: plaintext, secret: signing_secret, ip: '10.147.100.5')
    ts = Time.current.to_i.to_s
    nonce = SecureRandom.uuid
    h = {
      'X-Provisioner-Timestamp' => ts,
      'X-Provisioner-Nonce' => nonce,
      'X-Provisioner-Signature' => OpenSSL::HMAC.hexdigest('sha256', secret.to_s, "#{ts}.#{nonce}.#{body}"),
      'X-Provisioner-Client' => 'hermes-1',
      'CONTENT_TYPE' => 'application/json',
      'REMOTE_ADDR' => ip
    }
    h['Authorization'] = "Bearer #{token}" if token
    h
  end

  describe '1. IP específica: solo esa IP' do
    it 'permite exactamente la IP configurada' do
      body = ''
      get '/api/provisioner/catalog', headers: headers_for(body, ip: '10.147.100.5')
      expect(response).to have_http_status(:ok)
    end

    it 'rechaza la IP vecina (.6) aunque esté en la misma red' do
      body = ''
      get '/api/provisioner/catalog', headers: headers_for(body, ip: '10.147.100.6')
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('ip_not_allowed')
    end

    it 'rechaza una IP pública cualquiera' do
      body = ''
      get '/api/provisioner/catalog', headers: headers_for(body, ip: '8.8.8.8')
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe '2. Sin token no devuelve NADA (ni tools)' do
    it 'catalog sin token: 401 y CERO operaciones' do
      get '/api/provisioner/catalog', headers: headers_for('', token: nil)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).not_to have_key('operations')
      expect(response.body).not_to include('accounts')
    end

    it 'execute sin token: 401 y sin datos' do
      body = { operation: 'accounts.list' }.to_json
      post '/api/provisioner/execute', params: body, headers: headers_for(body, token: nil)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).not_to have_key('data')
    end

    it 'con token inventado: 401 y sin filtrar si el token existe o no' do
      get '/api/provisioner/catalog', headers: headers_for('', token: 'inventado-tlan')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('invalid_token')
      expect(response.parsed_body).not_to have_key('operations')
    end

    it 'con token correcto pero SIN firma: 401 y sin tools' do
      get '/api/provisioner/catalog',
          headers: { 'Authorization' => "Bearer #{plaintext}", 'REMOTE_ADDR' => '10.147.100.5' }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).not_to have_key('operations')
    end

    it 'ninguna respuesta sin autenticar filtra el token ni el secreto' do
      get '/api/provisioner/catalog', headers: headers_for('', token: nil)

      expect(response.body).not_to include(plaintext)
      expect(response.body).not_to include(signing_secret)
    end
  end

  describe '3. Con token: solo las tools de sus permisos' do
    it 'el catálogo expone SOLO lo permitido (accounts.view)' do
      get '/api/provisioner/catalog', headers: headers_for('')

      ops = response.parsed_body['operations']
      expect(ops.keys).to eq(['accounts.list', 'accounts.get'])
      # Nada de crear/editar, ni otros recursos, ni nada de borrar.
      expect(ops.keys).not_to include('accounts.create', 'accounts.update', 'users.list', 'plans.create')
      expect(ops.keys.grep(/delete|destroy/i)).to be_empty
    end

    it 'ejecutar una tool fuera del catálogo se deniega aunque el token sea válido' do
      body = { operation: 'users.list', params: {} }.to_json
      post '/api/provisioner/execute', params: body, headers: headers_for(body)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('permission_denied')
      expect(response.parsed_body).not_to have_key('data')
    end

    it 'al ampliar permisos el catálogo crece de inmediato (sin caché)' do
      JabvoxProvisionerApiToken.current_active.update!(
        permissions_jabvox: { 'accounts' => %w[view], 'users' => %w[view] }
      )

      get '/api/provisioner/catalog', headers: headers_for('')

      expect(response.parsed_body['operations'].keys).to include('users.list')
    end

    it 'al revocar el token el catálogo queda vacío y no responde' do
      JabvoxProvisionerApiToken.current_active.revoke!

      get '/api/provisioner/catalog', headers: headers_for('')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).not_to have_key('operations')
    end
  end
end
