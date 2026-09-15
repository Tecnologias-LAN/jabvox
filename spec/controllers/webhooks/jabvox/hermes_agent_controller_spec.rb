require 'rails_helper'

# El action_token autentica QUÉ Hermes llama; la allowlist de IPs verifica que la llamada
# venga realmente de ese Hermes. Sin el segundo candado, un token filtrado ejecutaría tools
# sobre la cuenta desde cualquier punto de internet.
RSpec.describe Webhooks::Jabvox::HermesAgentController do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let!(:agent) do
    JabvoxHermesAgent.create!(
      account: account, user: user,
      name_jabvox: 'agente-uno', status_jabvox: 'active'
    )
  end

  let!(:connection) do
    conn = JabvoxHermesConnection.create!(
      account: account,
      name_jabvox: 'hermes-uno',
      hermes_agent_name_jabvox: 'hermes-uno',
      base_url_jabvox: 'https://hermes.example.com',
      allowed_ips_jabvox: ['203.0.113.5', '10.147.17.0/24']
    )
    JabvoxHermesAgentConnection.create!(hermes_connection: conn, hermes_agent: agent)
    conn
  end

  let(:token) { connection.reload.action_token_jabvox }

  def get_tools(ip:, bearer: token)
    request.headers['Authorization'] = "Bearer #{bearer}"
    request.headers['REMOTE_ADDR'] = ip
    get :tools
  end

  describe 'GET #tools' do
    context 'when the request comes from an allowed IP' do
      it 'answers for the exact public address' do
        get_tools(ip: '203.0.113.5')

        expect(response).to have_http_status(:ok)
      end

      # Los Hermes sobre ZeroTier llegan con IP de la red virtual: rango privado legítimo.
      it 'answers over the ZeroTier range' do
        get_tools(ip: '10.147.17.42')

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when the request comes from a disallowed IP' do
      it 'rejects a valid token used from elsewhere' do
        get_tools(ip: '45.77.167.167')

        expect(response).to have_http_status(:forbidden)
      end

      it 'rejects a private address outside the declared range' do
        get_tools(ip: '192.168.1.10')

        expect(response).to have_http_status(:forbidden)
      end
    end

    # Fail-closed: declarar la conexión no basta, hay que autorizar su origen.
    context 'when the connection declares no IPs' do
      before { connection.update!(allowed_ips_jabvox: []) }

      it 'rejects even from a plausible address' do
        get_tools(ip: '203.0.113.5')

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with a bad token' do
      it 'rejects before even looking at the IP' do
        get_tools(ip: '203.0.113.5', bearer: 'no-es-un-token')

        expect(response).to have_http_status(:unauthorized)
      end
    end

    # Los tres candados son independientes y se exigen todos: el token identifica la
    # conexión, el sufijo -<account_id> ata ese token a su cuenta, y la allowlist exige que
    # el request venga del propio Hermes.
    describe 'the three locks' do
      it 'rejects a token whose account suffix was tampered with' do
        tampered = token.sub(/-\d+\z/, "-#{account.id + 999}")

        get_tools(ip: '203.0.113.5', bearer: tampered)

        expect(response).to have_http_status(:unauthorized)
      end

      it 'accepts only when token, account and IP all line up' do
        get_tools(ip: '203.0.113.5')

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['account_id']).to eq(account.id)
      end
    end

    # Un atacante no debe poder distinguir "token inválido" de "IP no autorizada": la
    # respuesta va sin cuerpo ni pistas sobre qué candado falló.
    describe 'response opacity' do
      it 'returns an empty body when the IP is rejected' do
        get_tools(ip: '45.77.167.167')

        expect(response.body).to be_blank
      end

      it 'returns an empty body when the token is rejected' do
        get_tools(ip: '203.0.113.5', bearer: 'no-es-un-token')

        expect(response.body).to be_blank
      end
    end
  end
end
