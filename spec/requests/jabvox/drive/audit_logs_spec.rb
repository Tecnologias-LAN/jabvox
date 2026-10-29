# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Jabvox::Drive::AuditLogs', type: :request do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true) }
  let(:other) { create(:account, jabvox_drive_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def path(acc) = "/api/v1/accounts/#{acc.id}/jabvox/drive/audit_logs"

  before do
    create(:jabvox_drive_audit_log, account: account, action: 'upload', user: admin)
    create(:jabvox_drive_audit_log, account: account, action: 'download', user: agent)
    create(:jabvox_drive_audit_log, account: other, action: 'delete')
  end

  it 'un admin ve el historial de SU cuenta (y no el de otra)' do
    get path(account), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    actions = response.parsed_body['payload'].map { |l| l['action'] }
    expect(actions).to contain_exactly('upload', 'download')
    expect(actions).not_to include('delete') # es de otra cuenta
  end

  it 'un agente NO puede ver el historial (solo admins)' do
    get path(account), headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
  end

  it 'filtra por acción' do
    get "#{path(account)}?action_name=upload", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].map { |l| l['action'] }).to eq(['upload'])
  end

  it 'no es accesible sin autenticación' do
    get path(account)
    expect(response).to have_http_status(:unauthorized)
  end
end
