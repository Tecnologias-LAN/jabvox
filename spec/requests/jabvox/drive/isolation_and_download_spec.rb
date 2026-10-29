# frozen_string_literal: true

require 'rails_helper'

# Pruebas de REQUEST (end-to-end HTTP) del aislamiento entre cuentas y de la
# descarga segura del Drive. Es el criterio de aceptación principal verificado al
# nivel del endpoint: una empresa NO puede leer ni tocar archivos de otra.
RSpec.describe 'Api::V1::Accounts::Jabvox::Drive aislamiento', :minio, type: :request do
  let(:account_a) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:account_b) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:admin_a) { create(:user, account: account_a, role: :administrator) }
  let(:admin_b) { create(:user, account: account_b, role: :administrator) }
  let(:agent_b) { create(:user, account: account_b, role: :agent) }

  before do
    skip 'MinIO no disponible' unless Jabvox::Drive::StorageService.configured? &&
                                      Jabvox::Drive::StorageService.new(account_a).available?
  end

  # Crea un archivo real en el Drive de A.
  def file_in_a(bytes: 'secreto de A', content_type: 'text/plain', filename: 'a.txt')
    Jabvox::Drive::OverflowService.new(account_a).ingest!(filename: filename, content_type: content_type, bytes: bytes)
  end

  after do
    account_a.jabvox_drive_files.each { |f| Jabvox::Drive::StorageService.new(account_a).delete(f.object_key) rescue nil } # rubocop:disable Style/RescueModifier
  end

  describe 'cross-account' do
    it 'B no puede ver el archivo de A por su id (404)' do
      file = file_in_a
      get "/api/v1/accounts/#{account_b.id}/jabvox/drive/files/#{file.id}",
          headers: admin_b.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'B no puede descargar el archivo de A por su id (404)' do
      file = file_in_a
      get "/api/v1/accounts/#{account_b.id}/jabvox/drive/files/#{file.id}/download",
          headers: admin_b.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'B no puede borrar el archivo de A' do
      file = file_in_a
      delete "/api/v1/accounts/#{account_b.id}/jabvox/drive/files/#{file.id}",
             headers: admin_b.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      expect(account_a.jabvox_drive_files.kept.exists?(file.id)).to be(true)
    end

    it 'A sí puede ver su propio archivo' do
      file = file_in_a
      get "/api/v1/accounts/#{account_a.id}/jabvox/drive/files/#{file.id}",
          headers: admin_a.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(file.id)
      # el serializer NO expone el object_key interno de MinIO
      expect(response.parsed_body).not_to have_key('object_key')
    end
  end

  describe 'descarga segura (anti-XSS)' do
    it 'un SVG se sirve como descarga (attachment) por streaming, nunca inline' do
      svg = file_in_a(bytes: '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
                      content_type: 'image/svg+xml', filename: 'x.svg')
      get "/api/v1/accounts/#{account_a.id}/jabvox/drive/files/#{svg.id}/download",
          headers: admin_a.create_new_auth_token
      # No redirige a MinIO: se sirve por stream con cabeceras seguras.
      expect(response.headers['Content-Disposition']).to start_with('attachment')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    end
  end

  describe 'roles' do
    it 'un agente de B no puede borrar (403)' do
      # archivo en B
      file_b = Jabvox::Drive::OverflowService.new(account_b).ingest!(filename: 'b.txt', content_type: 'text/plain', bytes: 'de B')
      delete "/api/v1/accounts/#{account_b.id}/jabvox/drive/files/#{file_b.id}",
             headers: agent_b.create_new_auth_token
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      Jabvox::Drive::StorageService.new(account_b).delete(file_b.object_key) rescue nil # rubocop:disable Style/RescueModifier
    end
  end
end
