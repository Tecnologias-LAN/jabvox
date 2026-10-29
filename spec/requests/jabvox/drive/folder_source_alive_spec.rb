# frozen_string_literal: true

require 'rails_helper'

# La carpeta de un contacto trae `source_alive` para pintar la bolita:
#   true  -> el contacto existe (verde).
#   false -> el contacto fue eliminado; los archivos se conservan (roja, huérfana).
#   nil   -> no es carpeta de contacto (raíz "contactos" o carpetas manuales).
RSpec.describe 'Api::V1::Accounts::Jabvox::Drive carpeta source_alive', type: :request do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'María Rojas') }

  def folders_payload(parent_id)
    get "/api/v1/accounts/#{account.id}/jabvox/drive/folders",
        params: { parent_id: parent_id }, headers: admin.create_new_auth_token
    response.parsed_body['payload']
  end

  it 'la carpeta de un contacto VIVO trae source_alive=true' do
    folder = JabvoxDriveFolder.for_contact(account, contact)
    payload = folders_payload(folder.parent_id)
    row = payload.find { |f| f['id'] == folder.id }
    expect(row['source_alive']).to be(true)
  end

  it 'si el contacto se elimina, la carpeta queda y trae source_alive=false' do
    folder = JabvoxDriveFolder.for_contact(account, contact)
    contact_id = contact.id
    contact.destroy!

    # La carpeta sobrevive (no se borra con el contacto).
    expect(JabvoxDriveFolder.exists?(folder.id)).to be(true)
    expect(folder.reload.contact_id).to eq(contact_id) # conserva la referencia histórica

    row = folders_payload(folder.parent_id).find { |f| f['id'] == folder.id }
    expect(row['source_alive']).to be(false)
  end

  it 'la raíz contactos/ (no es de contacto) trae source_alive=nil' do
    root = JabvoxDriveFolder.contacts_root(account)
    row = folders_payload(root.parent_id).find { |f| f['id'] == root.id }
    expect(row['source_alive']).to be_nil
  end
end
