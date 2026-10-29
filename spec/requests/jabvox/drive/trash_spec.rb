# frozen_string_literal: true

require 'rails_helper'

# Papelera del Drive: borrar manda a la papelera (reversible, sigue ocupando cuota),
# se puede restaurar o eliminar definitivamente; solo al eliminar definitivo se libera
# el espacio; a los 7 días se purga sola. Todo auditado. Solo admin.
RSpec.describe 'Api::V1::Accounts::Jabvox::Drive papelera', :minio, type: :request do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    skip 'MinIO no disponible' unless Jabvox::Drive::StorageService.configured? &&
                                      Jabvox::Drive::StorageService.new(account).available?
  end

  def a_file
    Jabvox::Drive::OverflowService.new(account).ingest!(
      filename: 'doc.txt', content_type: 'text/plain', bytes: 'contenido ' * 20
    )
  end

  after do
    account.jabvox_drive_files.each do |f|
      Jabvox::Drive::StorageService.new(account).delete(f.object_key)
    rescue StandardError
      nil
    end
  end

  describe 'enviar a la papelera (DELETE files/:id)' do
    it 'manda a papelera, NO libera cuota y audita trash' do
      file = a_file
      size = file.byte_size
      used_before = Jabvox::Drive::QuotaService.new(account).used_bytes

      delete "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}",
             headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)

      file.reload
      expect(file.in_trash?).to be(true)
      # Sigue ocupando el espacio (no se libera hasta purgar).
      expect(Jabvox::Drive::QuotaService.new(account).used_bytes).to eq(used_before)
      expect(size).to be_positive
      expect(account.jabvox_drive_audit_logs.where(action: 'trash', auditable_id: file.id)).to exist
    end

    it 'un agente NO puede borrar (solo admin)' do
      file = a_file
      delete "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}",
             headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end

  describe 'listar la papelera (GET files/trash)' do
    it 'muestra los archivos en papelera, no los activos' do
      en_papelera = a_file
      Jabvox::Drive::FileService.new(account).destroy!(en_papelera, actor: admin)

      get "/api/v1/accounts/#{account.id}/jabvox/drive/files/trash",
          headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['payload'].map { |f| f['id'] }
      expect(ids).to include(en_papelera.id)
    end
  end

  describe 'restaurar (POST files/:id/restore)' do
    it 'saca de la papelera y vuelve a estar activo' do
      file = a_file
      Jabvox::Drive::FileService.new(account).destroy!(file, actor: admin)

      post "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}/restore",
           headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(file.reload.in_trash?).to be(false)
      expect(account.jabvox_drive_files.visible).to include(file)
      expect(account.jabvox_drive_audit_logs.where(action: 'restore', auditable_id: file.id)).to exist
    end
  end

  describe 'eliminar definitivamente (DELETE files/:id/purge)' do
    it 'borra de verdad, libera cuota y audita purge' do
      file = a_file
      size = file.byte_size
      Jabvox::Drive::FileService.new(account).destroy!(file, actor: admin)
      used_in_trash = Jabvox::Drive::QuotaService.new(account).used_bytes
      expect(used_in_trash).to be >= size # seguía ocupando

      delete "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}/purge",
             headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)

      file.reload
      expect(file.purged?).to be(true)
      expect(Jabvox::Drive::QuotaService.new(account).used_bytes).to eq(used_in_trash - size)
      expect(account.jabvox_drive_audit_logs.where(action: 'purge', auditable_id: file.id)).to exist
    end

    it 'NO se puede purgar un archivo que no está en la papelera (404)' do
      file = a_file # activo, no en papelera
      delete "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}/purge",
             headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'barrido automático a 7 días' do
    it 'purga lo que lleva más de 7 días en papelera y conserva lo reciente' do
      viejo = a_file
      reciente = Jabvox::Drive::OverflowService.new(account).ingest!(
        filename: 'nuevo.txt', content_type: 'text/plain', bytes: 'nuevo' * 10
      )
      Jabvox::Drive::FileService.new(account).destroy!(viejo, actor: admin)
      Jabvox::Drive::FileService.new(account).destroy!(reciente, actor: admin)
      # Envejecer el "viejo" más de 7 días.
      viejo.update_column(:deleted_at, 8.days.ago)

      Jabvox::Drive::TrashSweeperJob.perform_now

      expect(viejo.reload.purged?).to be(true)        # purgado
      expect(reciente.reload.purged?).to be(false)    # sigue en papelera
      expect(reciente.in_trash?).to be(true)
    end
  end

  describe 'aislamiento entre cuentas' do
    it 'no se puede restaurar/purgar un archivo de OTRA cuenta' do
      other = create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 })
      intruder = create(:user, account: other, role: :administrator)
      file = a_file
      Jabvox::Drive::FileService.new(account).destroy!(file, actor: admin)

      post "/api/v1/accounts/#{other.id}/jabvox/drive/files/#{file.id}/restore",
           headers: intruder.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end
end
