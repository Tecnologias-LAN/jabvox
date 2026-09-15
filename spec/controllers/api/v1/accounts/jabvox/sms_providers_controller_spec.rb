# frozen_string_literal: true

require 'rails_helper'

# check_connection hacía TCPSocket.new directo al host que el admin configura en base_url,
# sin pasar por ningún guard SSRF — permitía usar el endpoint para escanear la red interna
# del servidor (loopback, RFC1918, metadata cloud). Ahora reutiliza el HostGuardService de
# Analytics para bloquear esos rangos antes de intentar la conexión.
RSpec.describe 'Api::V1::Accounts::Jabvox::SmsProviders#check_connection', type: :request do
  let(:account) { create(:account, jabvox_sms_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:provider) do
    JabvoxSmsProvider.create!(account: account, name: 'Vozip', base_url: 'https://sms.example.com',
                              api_user: 'user', api_password: 'pass')
  end

  def check_connection(base_url)
    provider.update!(base_url: base_url)
    get "/api/v1/accounts/#{account.id}/jabvox/sms_providers/#{provider.id}/check_connection",
        headers: admin.create_new_auth_token, as: :json
  end

  it 'rejects loopback addresses (SSRF)' do
    check_connection('http://127.0.0.1:5432')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['connected']).to be false
  end

  it 'rejects cloud metadata addresses (SSRF), even with private networks allowed elsewhere' do
    check_connection('http://169.254.169.254')
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects private network ranges (SSRF)' do
    check_connection('http://192.168.1.1')
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'allows a public host on an allowed port and reports the real reachability' do
    allow(Jabvox::Analytics::HostGuardService).to receive(:new).and_return(
      instance_double(Jabvox::Analytics::HostGuardService,
                      call: instance_double(Jabvox::Analytics::HostGuardService::Result, allowed?: true, reason: 'ok'))
    )
    allow_any_instance_of(Api::V1::Accounts::Jabvox::SmsProvidersController) # rubocop:disable RSpec/AnyInstance
      .to receive(:tcp_reachable?).and_return(true)
    check_connection('https://sms.example.com')
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['connected']).to be true
  end
end
