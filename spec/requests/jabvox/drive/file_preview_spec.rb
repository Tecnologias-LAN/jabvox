# frozen_string_literal: true

require 'rails_helper'

# Verifica que el Drive ABRE (sirve para previsualizar) la mayoría de tipos de
# archivo, no solo imágenes: JSON, CSV, TXT, Word (.docx) y Excel (.xlsx).
#
# El criterio de "abrir" en el navegador es: el endpoint de descarga con ?stream=1
# devuelve EXACTAMENTE los mismos bytes (round-trip íntegro) y el content_type
# correcto, para que el visor del front (texto/tabla/mammoth/SheetJS) lo renderice.
# Todo pasa por el stream privado del Drive; nunca por una URL pública de MinIO.
RSpec.describe 'Api::V1::Accounts::Jabvox::Drive previsualización por tipo', :minio, type: :request do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before do
    skip 'MinIO no disponible' unless Jabvox::Drive::StorageService.configured? &&
                                      Jabvox::Drive::StorageService.new(account).available?
  end

  after do
    account.jabvox_drive_files.each do |f|
      Jabvox::Drive::StorageService.new(account).delete(f.object_key)
    rescue StandardError
      nil
    end
  end

  # Sube bytes reales al Drive dejando que el backend detecte el MIME por magic bytes.
  def upload(filename, bytes)
    Jabvox::Drive::FileService.new(account).upload!(
      bytes: bytes, filename: filename, content_type: nil, created_by: admin
    )
  end

  # .docx / .xlsx mínimos válidos (OOXML = zip). Suficiente para que Marcel detecte
  # el MIME y para comprobar el round-trip íntegro de bytes.
  def ooxml(content_type_part, doc_xml)
    require 'zip'
    buffer = Zip::OutputStream.write_buffer do |z|
      z.put_next_entry('[Content_Types].xml')
      z.write(<<~XML)
        <?xml version="1.0"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/#{content_type_part}"/></Types>
      XML
      z.put_next_entry('_rels/.rels')
      z.write('<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>')
      z.put_next_entry(content_type_part)
      z.write(doc_xml)
    end
    buffer.string
  end

  # Descarga por HTTP real (?stream=1) tal como lo hace el navegador al previsualizar.
  def download_stream(file)
    get "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}/download?stream=1",
        headers: admin.create_new_auth_token
  end

  {
    'datos.json' => { bytes: '{"empresa":"Jabvox","ok":true}', expect_ct: /json/ },
    'reporte.csv' => { bytes: "id,nombre\n1,Ana\n2,Luis\n", expect_ct: %r{csv|text/plain} },
    'nota.txt' => { bytes: "Texto plano con acentos: ñ á é.\n", expect_ct: %r{text/plain} }
  }.each do |filename, cfg|
    it "sirve #{filename} íntegro y con content_type de texto" do
      file = upload(filename, cfg[:bytes])
      download_stream(file)

      expect(response).to have_http_status(:ok)
      expect(response.body.b).to eq(cfg[:bytes].b)
      expect(file.content_type).to match(cfg[:expect_ct])
      # Cabecera de seguridad: nunca se interpreta por sniffing.
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    end
  end

  it 'sirve un .docx íntegro y lo detecta como Word' do
    ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    doc = %(<?xml version="1.0"?><w:document xmlns:w="#{ns}"><w:body>)
    bytes = ooxml('word/document.xml', doc)
    file = upload('carta.docx', bytes)
    download_stream(file)

    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(bytes.b)
    expect(file.content_type).to include('wordprocessingml.document').or include('zip')
  end

  it 'sirve un .xlsx íntegro' do
    bytes = ooxml('xl/workbook.xml',
                  '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>')
    file = upload('hoja.xlsx', bytes)
    download_stream(file)

    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(bytes.b)
  end

  it 'registra en auditoría cada apertura/descarga (historial)' do
    file = upload('datos.json', '{"a":1}')
    expect { download_stream(file) }
      .to change { account.jabvox_drive_audit_logs.where(action: 'download').count }.by(1)
  end

  # Descarga SIN ?stream=1 (comportamiento por defecto del navegador).
  def download_default(file)
    get "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}/download",
        headers: admin.create_new_auth_token
  end

  describe 'ejecutables y scripts (solo almacenamiento, nunca se ejecutan)' do
    %w[virus.exe script.bat install.sh app.msi run.ps1 macro.vbs lib.dll setup.cmd].each do |filename|
      it "sirve #{filename} como attachment, por streaming, con nosniff (no inline)" do
        file = upload(filename, "contenido binario de #{filename}")
        # Aunque el navegador pida descarga por defecto (sin ?stream=1), un ejecutable
        # NO redirige a MinIO: se fuerza streaming desde la app como attachment.
        download_default(file)

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Disposition']).to start_with('attachment')
        expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
        # Nunca con un Content-Type que invite al navegador a ejecutar/interpretar.
        expect(response.headers['Content-Type']).not_to match(%r{text/html}i)
      end
    end

    it 'un .exe disfrazado con content_type de imagen igual se fuerza a attachment' do
      # El atacante sube un .exe declarando image/png para intentar preview inline.
      file = Jabvox::Drive::FileService.new(account).upload!(
        bytes: 'MZ...binario...', filename: 'payload.exe',
        content_type: 'image/png', created_by: admin
      )
      download_default(file)

      expect(response.headers['Content-Disposition']).to start_with('attachment')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    end
  end

  describe 'endpoints protegidos' do
    it 'sin autenticación: 401' do
      file = upload('datos.json', '{"a":1}')
      get "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}/download"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'otra cuenta no puede descargar el archivo (404, aislamiento)' do
      other = create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 })
      intruder = create(:user, account: other, role: :administrator)
      file = upload('secreto.json', '{"secreto":true}')
      get "/api/v1/accounts/#{other.id}/jabvox/drive/files/#{file.id}/download",
          headers: intruder.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'seguridad de MinIO (no exponer host ni credenciales)' do
    it 'con JABVOX_DRIVE_ALWAYS_STREAM=true nunca redirige a MinIO; sirve por la app' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('JABVOX_DRIVE_ALWAYS_STREAM', false).and_return('true')
      file = upload('datos.json', '{"a":1}')

      get "/api/v1/accounts/#{account.id}/jabvox/drive/files/#{file.id}/download",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)        # stream, NO 302 redirect
      expect(response.headers['Location']).to be_nil   # no hay redirect a MinIO
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.body.b).to eq('{"a":1}'.b)
    end
  end
end
