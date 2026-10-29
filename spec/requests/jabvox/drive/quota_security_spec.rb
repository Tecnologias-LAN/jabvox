# frozen_string_literal: true

require 'rails_helper'

# Seguridad de la cuota: un usuario (ni admin de la cuenta) puede aumentar su propio
# almacenamiento. La cuota (limits.storage_gb) solo la cambian super admin / plataforma
# / billing. Además, no se puede exceder la cuota subiendo archivos.
RSpec.describe 'Api::V1::Accounts::Jabvox::Drive seguridad de cuota', :minio, type: :request do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before do
    skip 'MinIO no disponible' unless Jabvox::Drive::StorageService.configured? &&
                                      Jabvox::Drive::StorageService.new(account).available?
  end

  it 'el admin de la cuenta NO puede cambiar limits.storage_gb vía la API de cuenta' do
    patch "/api/v1/accounts/#{account.id}",
          params: { limits: { storage_gb: 999_999 } },
          headers: admin.create_new_auth_token

    account.reload
    expect(account.limits['storage_gb'].to_i).to eq(1) # no cambió
  end

  it 'no se puede exceder la cuota: una subida que no cabe se RECHAZA' do
    # Cuota efectiva diminuta para la prueba.
    allow_any_instance_of(Jabvox::Drive::QuotaService).to receive(:quota_bytes).and_return(10)

    post "/api/v1/accounts/#{account.id}/jabvox/drive/files",
         params: { file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') },
         headers: admin.create_new_auth_token

    # Se rechaza (402 por cuota o 422 por validación): lo clave es que NO se crea.
    expect(response).to have_http_status(:payment_required).or have_http_status(:unprocessable_content)
    expect(account.jabvox_drive_files.kept.where(filename: 'avatar.png')).not_to exist
  end

  it 'el endpoint de storage es SOLO lectura (no hay forma de escribir el contador)' do
    routes = Rails.application.routes.routes.map { |r| "#{r.verb} #{r.path.spec}" }
    storage_routes = routes.select { |r| r.include?('jabvox/drive/storage') }
    # Solo debe existir el GET (index); nunca POST/PUT/PATCH/DELETE sobre storage.
    expect(storage_routes).to(be_all { |r| r.start_with?('GET') })
  end
end
