# frozen_string_literal: true

# rubocop:disable RSpec/ContextWording
require 'rails_helper'

# SEGURIDAD RBAC del Drive (backend, no manipulable desde el frontend):
#
#   - Agentes y ROLES PERSONALIZADOS: solo pueden VER y DESCARGAR archivos.
#   - Solo los ADMINISTRADORES: cargan, eliminan (papelera), renombran, mueven,
#     restauran y purgan, y crean/renombran/borran carpetas.
#   - La PAPELERA y el HISTORIAL (audit logs) solo los ve un administrador.
#
# No hay forma de que un no-admin elimine o cargue: toda acción de escritura pasa
# por Pundit (authorize) y la policy exige administrator?. Un rol personalizado se
# guarda con role=agent, así que administrator? es false para él.
RSpec.describe 'Drive RBAC: solo admin escribe; agentes/custom roles solo leen', type: :request do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  # Agente normal.
  let(:agent) { create(:user, account: account, role: :agent) }

  # Rol PERSONALIZADO: usuario con role=agent + custom_role con TODOS los permisos.
  # Aun con permisos personalizados, NO es administrator? → solo lectura en el Drive.
  let(:custom_user) { create(:user) }
  let(:custom_role) { create(:custom_role, account: account, permissions: CustomRole::PERMISSIONS) }
  # Vincula custom_user a la cuenta con el rol personalizado; se usa indirectamente
  # al autenticar como custom_user en los ejemplos compartidos.
  let!(:custom_account_user) do # rubocop:disable RSpec/LetSetup
    create(:account_user, account: account, user: custom_user, role: :agent, custom_role: custom_role)
  end

  let(:folder) do
    account.jabvox_drive_folders.create!(name: 'carpeta', path: '/carpeta/', created_by: admin)
  end

  let(:file) do
    account.jabvox_drive_files.create!(
      filename: 'doc.txt', content_type: 'text/plain', byte_size: 10,
      object_key: "acct-#{account.id}/files/ab/#{SecureRandom.hex(8)}",
      bucket: JabvoxDriveFile::BUCKET_PRIMARY, status: :available
    )
  end

  let(:trashed_file) do
    account.jabvox_drive_files.create!(
      filename: 'borrado.txt', content_type: 'text/plain', byte_size: 10,
      object_key: "acct-#{account.id}/files/cd/#{SecureRandom.hex(8)}",
      bucket: JabvoxDriveFile::BUCKET_PRIMARY, status: :available,
      deleted_at: Time.current, trashed_by: admin
    )
  end

  def base
    "/api/v1/accounts/#{account.id}/jabvox/drive"
  end

  # Un no-admin que intenta escribir recibe un estado de "no autorizado".
  # (Pundit::NotAuthorizedError → el handler global responde 401/403/404.)
  def expect_blocked
    expect(response.status).to be_in([401, 403, 404])
  end

  # ---- LECTURA: agentes y custom roles SÍ pueden ----
  shared_examples 'puede leer' do |token_name|
    it "#{token_name}: lista archivos (index)" do
      get "#{base}/files", headers: send(token_name).create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it "#{token_name}: lista carpetas (index)" do
      get "#{base}/folders", headers: send(token_name).create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it "#{token_name}: ve un archivo (show)" do
      get "#{base}/files/#{file.id}", headers: send(token_name).create_new_auth_token
      expect(response).to have_http_status(:ok)
    end
  end

  # ---- ESCRITURA / GESTIÓN: solo admin; no-admin SIEMPRE bloqueado ----
  shared_examples 'NO puede escribir ni gestionar' do |token_name|
    let(:headers) { send(token_name).create_new_auth_token }

    it "#{token_name}: NO puede subir (create file)" do
      upload = Rack::Test::UploadedFile.new(StringIO.new('x'), 'text/plain', original_filename: 'x.txt')
      post "#{base}/files", params: { file: upload, filename: 'x.txt' }, headers: headers
      expect_blocked
    end

    it "#{token_name}: NO puede renombrar/mover (update file)" do
      patch "#{base}/files/#{file.id}", params: { filename: 'hack.txt' }, headers: headers
      expect_blocked
      expect(file.reload.filename).to eq('doc.txt') # no cambió
    end

    it "#{token_name}: NO puede enviar a la papelera (destroy file)" do
      delete "#{base}/files/#{file.id}", headers: headers
      expect_blocked
      expect(file.reload.deleted_at).to be_nil # sigue vivo
    end

    it "#{token_name}: NO puede ver la papelera (trash)" do
      get "#{base}/files/trash", headers: headers
      expect_blocked
    end

    it "#{token_name}: NO puede restaurar (restore)" do
      post "#{base}/files/#{trashed_file.id}/restore", headers: headers
      expect_blocked
      expect(trashed_file.reload.deleted_at).to be_present # sigue en papelera
    end

    it "#{token_name}: NO puede purgar (purge)" do
      delete "#{base}/files/#{trashed_file.id}/purge", headers: headers
      expect_blocked
      expect(trashed_file.reload.purged_at).to be_nil # no se purgó
    end

    it "#{token_name}: NO puede crear carpeta" do
      post "#{base}/folders", params: { name: 'nueva' }, headers: headers
      expect_blocked
    end

    it "#{token_name}: NO puede renombrar carpeta" do
      patch "#{base}/folders/#{folder.id}", params: { name: 'renombrada' }, headers: headers
      expect_blocked
      expect(folder.reload.name).to eq('carpeta')
    end

    it "#{token_name}: NO puede borrar carpeta" do
      delete "#{base}/folders/#{folder.id}", headers: headers
      expect_blocked
      expect(JabvoxDriveFolder.exists?(folder.id)).to be(true)
    end

    it "#{token_name}: NO puede ver el historial (audit logs)" do
      get "#{base}/audit_logs", headers: headers
      expect_blocked
    end
  end

  context 'agente normal' do
    it_behaves_like 'puede leer', :agent
    it_behaves_like 'NO puede escribir ni gestionar', :agent
  end

  context 'rol personalizado (role=agent + custom_role con TODOS los permisos)' do
    it_behaves_like 'puede leer', :custom_user
    it_behaves_like 'NO puede escribir ni gestionar', :custom_user
  end

  context 'administrador' do
    it 'SÍ puede subir, borrar y ver papelera e historial' do
      upload = Rack::Test::UploadedFile.new(StringIO.new('x'), 'text/plain', original_filename: 'x.txt')
      post "#{base}/files", params: { file: upload, filename: 'x.txt' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:created)

      delete "#{base}/files/#{file.id}", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(file.reload.deleted_at).to be_present

      get "#{base}/files/trash", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)

      get "#{base}/audit_logs", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end
  end

  # ---- ESTRÉS: ninguna combinación de permisos personalizados habilita escritura ----
  context 'estrés: ningún subconjunto de permisos de custom_role permite eliminar/cargar' do
    it 'con cada permiso personalizado por separado, destroy y create siguen bloqueados' do
      CustomRole::PERMISSIONS.each do |perm|
        role = create(:custom_role, account: account, permissions: [perm])
        user = create(:user)
        create(:account_user, account: account, user: user, role: :agent, custom_role: role)
        headers = user.create_new_auth_token

        # Intento de borrado
        delete "#{base}/files/#{file.id}", headers: headers
        expect(response.status).to(be_in([401, 403, 404]), "permiso '#{perm}' permitió DESTROY")
        expect(file.reload.deleted_at).to be_nil

        # Intento de carga
        upload = Rack::Test::UploadedFile.new(StringIO.new('x'), 'text/plain', original_filename: 'x.txt')
        post "#{base}/files", params: { file: upload, filename: 'x.txt' }, headers: headers
        expect(response.status).to(be_in([401, 403, 404]), "permiso '#{perm}' permitió CREATE")
      end
    end

    it 'repetir el intento de borrado muchas veces nunca cuela (idempotencia del bloqueo)' do
      headers = agent.create_new_auth_token
      20.times do
        delete "#{base}/files/#{file.id}", headers: headers
        expect(response.status).to be_in([401, 403, 404])
      end
      expect(file.reload.deleted_at).to be_nil
    end
  end
end

# rubocop:enable RSpec/ContextWording
