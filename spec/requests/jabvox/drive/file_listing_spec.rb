# frozen_string_literal: true

require 'rails_helper'

# El listado de archivos del Drive navega carpeta por carpeta:
# - En la RAÍZ (sin folder_id) solo salen los archivos SUELTOS (folder_id NULL),
#   NO los que están en subcarpetas (si no, se verían "duplicados" arriba y dentro).
# - Dentro de una carpeta salen solo sus archivos.
# - Al buscar/filtrar la búsqueda es global.
RSpec.describe 'Api::V1::Accounts::Jabvox::Drive listado por carpeta', type: :request do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:folder) { create(:jabvox_drive_folder, account: account, name: 'sub', path: '/sub/') }

  def drive_file(name, folder_id: nil)
    account.jabvox_drive_files.create!(
      filename: name, content_type: 'text/plain', byte_size: 10,
      object_key: "acct-#{account.id}/x/#{SecureRandom.hex(6)}",
      bucket: JabvoxDriveFile::BUCKET_PRIMARY, status: :available, folder_id: folder_id
    )
  end

  def list(params = {})
    get "/api/v1/accounts/#{account.id}/jabvox/drive/files",
        params: params, headers: admin.create_new_auth_token
    response.parsed_body['payload'].map { |f| f['filename'] }
  end

  before do
    drive_file('suelto.txt')                      # en la raíz
    drive_file('dentro.txt', folder_id: folder.id) # en subcarpeta
  end

  it 'en la RAÍZ muestra solo los archivos sueltos, no los de subcarpetas' do
    names = list # sin folder_id
    expect(names).to include('suelto.txt')
    expect(names).not_to include('dentro.txt')
  end

  it 'dentro de una carpeta muestra solo sus archivos' do
    names = list(folder_id: folder.id)
    expect(names).to include('dentro.txt')
    expect(names).not_to include('suelto.txt')
  end

  it 'al buscar, la búsqueda es GLOBAL (encuentra en cualquier carpeta)' do
    names = list(query: 'dentro')
    expect(names).to include('dentro.txt')
  end
end
