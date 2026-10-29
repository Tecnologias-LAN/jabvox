# frozen_string_literal: true

require 'rails_helper'

# Las carpetas de SISTEMA del Drive (contactos/ y las de cada contacto/bandeja) NO
# se pueden eliminar: son la estructura canónica. Los ARCHIVOS dentro sí se pueden
# borrar, y una carpeta creada por el usuario (aunque se llame igual) también.
RSpec.describe 'Api::V1::Accounts::Jabvox::Drive carpetas de sistema', type: :request do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'María Rojas') }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Ventas') }

  it 'NO permite eliminar la carpeta raíz contactos/ (sistema)' do
    root = JabvoxDriveFolder.contacts_root(account)
    expect(root.system_folder?).to be(true)

    delete "/api/v1/accounts/#{account.id}/jabvox/drive/folders/#{root.id}",
           headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_content)
    expect(JabvoxDriveFolder.exists?(root.id)).to be(true) # sigue existiendo
  end

  it 'NO permite eliminar la carpeta de un contacto (sistema)' do
    folder = JabvoxDriveFolder.for_contact(account, contact)
    expect(folder.system_folder?).to be(true)

    delete "/api/v1/accounts/#{account.id}/jabvox/drive/folders/#{folder.id}",
           headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_content)
    expect(JabvoxDriveFolder.exists?(folder.id)).to be(true)
  end

  it 'NO permite eliminar la carpeta de una bandeja dentro del contacto (sistema)' do
    folder = JabvoxDriveFolder.for_contact_inbox(account, contact, inbox)
    expect(folder.system_folder?).to be(true)

    delete "/api/v1/accounts/#{account.id}/jabvox/drive/folders/#{folder.id}",
           headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'SÍ permite eliminar una carpeta creada por el usuario, aunque se llame "contactos"' do
    # Una carpeta normal (no sistema) creada por el usuario.
    post "/api/v1/accounts/#{account.id}/jabvox/drive/folders",
         params: { name: 'contactos' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:created)
    folder_id = response.parsed_body['id']
    expect(JabvoxDriveFolder.find(folder_id).system_folder?).to be(false)

    delete "/api/v1/accounts/#{account.id}/jabvox/drive/folders/#{folder_id}",
           headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(JabvoxDriveFolder.exists?(folder_id)).to be(false)
  end

  it 'expone system_folder en el payload (para marcar la estrella en la UI)' do
    JabvoxDriveFolder.for_contact(account, contact)
    get "/api/v1/accounts/#{account.id}/jabvox/drive/folders",
        params: { contact_id: contact.id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    # Al menos una carpeta de sistema en el payload.
    folders = response.parsed_body['payload'] || response.parsed_body
    expect(folders).to be_present
  end

  describe 'seguridad de acceso (sin sesión / otra cuenta)' do
    it 'sin autenticación NO se pueden listar carpetas (401)' do
      get "/api/v1/accounts/#{account.id}/jabvox/drive/folders"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'sin autenticación NO se puede crear una carpeta (401)' do
      post "/api/v1/accounts/#{account.id}/jabvox/drive/folders", params: { name: 'hack' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'un usuario de OTRA cuenta no puede operar sobre esta (401/403)' do
      other = create(:account, jabvox_drive_enabled_jabvox: true)
      intruder = create(:user, account: other, role: :administrator)
      get "/api/v1/accounts/#{account.id}/jabvox/drive/folders",
          headers: intruder.create_new_auth_token
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end
end
