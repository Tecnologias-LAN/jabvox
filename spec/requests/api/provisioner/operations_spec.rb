# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API Provisioner', type: :request do
  let(:allowed_ip) { '10.147.100.1' }
  let!(:generated) do
    JabvoxProvisionerApiToken.generate!(
      created_by_id: nil,
      allowed_ips: ['10.147.0.0/16'], # red ZeroTier completa
      permissions: { 'accounts' => %w[view] }
    )
  end
  let(:token_record) { generated[0] }
  let(:plaintext) { generated[1] }
  let(:signing_secret) { generated[2] }

  # Firma una petición como lo hace Hermes: HMAC-SHA256 de "{ts}.{nonce}.{cuerpo}".
  def signed_headers(body, **opts)
    token = opts.fetch(:token, plaintext)
    secret = opts.fetch(:secret, signing_secret)
    ip = opts.fetch(:ip, allowed_ip)
    client = opts.fetch(:client, 'hermes-prov-1')
    ts = opts[:ts] || Time.current.to_i.to_s
    nonce = opts[:nonce] || SecureRandom.uuid
    {
      'Authorization' => "Bearer #{token}",
      'X-Provisioner-Timestamp' => ts,
      'X-Provisioner-Nonce' => nonce,
      'X-Provisioner-Signature' => OpenSSL::HMAC.hexdigest('sha256', secret, "#{ts}.#{nonce}.#{body}"),
      'X-Provisioner-Client' => client,
      'CONTENT_TYPE' => 'application/json',
      'REMOTE_ADDR' => ip
    }
  end

  def post_execute(payload, **)
    body = payload.to_json
    post '/api/provisioner/execute', params: body, headers: signed_headers(body, **)
  end

  describe 'autenticación' do
    it 'acepta una petición bien firmada desde una IP de la red ZeroTier' do
      post_execute({ operation: 'accounts.list', params: {} })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to be(true)
    end

    it 'rechaza sin token' do
      body = { operation: 'accounts.list' }.to_json
      post '/api/provisioner/execute', params: body,
                                       headers: { 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => allowed_ip }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza un token inválido' do
      post_execute({ operation: 'accounts.list' }, token: 'token-falso-tlan')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('invalid_token')
    end

    it 'rechaza una IP fuera de la allowlist' do
      post_execute({ operation: 'accounts.list' }, ip: '8.8.8.8')

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('ip_not_allowed')
    end

    it 'rechaza una firma incorrecta' do
      post_execute({ operation: 'accounts.list' }, secret: 'secreto-equivocado')

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('bad_signature')
    end

    it 'rechaza un timestamp fuera de la ventana' do
      post_execute({ operation: 'accounts.list' }, ts: 10.minutes.ago.to_i.to_s)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('stale_timestamp')
    end

    it 'rechaza el replay del mismo nonce' do
      nonce = SecureRandom.uuid
      post_execute({ operation: 'accounts.list' }, nonce: nonce)
      expect(response).to have_http_status(:ok)

      post_execute({ operation: 'accounts.list' }, nonce: nonce)
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('replay')
    end

    it 'rechaza una segunda conexión con otra identidad de cliente' do
      post_execute({ operation: 'accounts.list' })
      expect(response).to have_http_status(:ok)

      post_execute({ operation: 'accounts.list' }, client: 'otro-cliente')

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('connection_conflict')
    end

    it 'rechaza si el token fue revocado desde el Super Admin' do
      token_record.revoke!

      post_execute({ operation: 'accounts.list' })

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'autorización por operación' do
    it 'deniega una operación sin permiso en el checklist' do
      post_execute({ operation: 'accounts.create', params: { 'name' => 'Nueva' } })

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('permission_denied')
      expect(Account.find_by(name: 'Nueva')).to be_nil
    end

    it 'deniega cualquier operación de borrado (no existe)' do
      post_execute({ operation: 'accounts.delete', params: { 'id' => 1 } })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('unknown_operation')
    end

    it 'ejecuta lo que se FIRMÓ, no params inyectados por query string' do
      body = { operation: 'accounts.list', params: {} }.to_json
      post '/api/provisioner/execute?operation=accounts.create',
           params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to have_key('accounts')
    end
  end

  describe 'GET /api/provisioner/catalog' do
    it 'lista solo las operaciones habilitadas para el token' do
      body = ''
      get '/api/provisioner/catalog', headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      ops = response.parsed_body['operations']
      expect(ops.keys).to include('accounts.list')
      expect(ops.keys).not_to include('accounts.create', 'plans.create')
    end

    it 'nunca incluye operaciones de borrado' do
      body = ''
      get '/api/provisioner/catalog', headers: signed_headers(body)

      expect(response.parsed_body['operations'].keys.grep(/delete|destroy/i)).to be_empty
    end
  end
end
