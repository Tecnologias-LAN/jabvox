# frozen_string_literal: true

require 'rails_helper'

# El panel "Uso del plan" (settings/general) lee este servicio. Debe reflejar el
# consumo real del Drive, no solo los adjuntos de mensajes: si no, la barra queda
# en 0 aunque la empresa tenga archivos, y la cuota no se respeta.
RSpec.describe Jabvox::StorageUsageService do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 5 }) }

  # Crea una fila de archivo del Drive directamente (sin tocar MinIO).
  def drive_file(content_type:, byte_size:, status: :available, deleted: false, purged: false)
    account.jabvox_drive_files.create!(
      filename: "f-#{SecureRandom.hex(4)}",
      content_type: content_type,
      byte_size: byte_size,
      sha256: SecureRandom.hex(32),
      object_key: "acct-#{account.id}/files/#{SecureRandom.hex(8)}",
      bucket: JabvoxDriveFile::BUCKET_PRIMARY,
      status: status,
      deleted_at: deleted || purged ? Time.current : nil,
      purged_at: purged ? Time.current : nil
    )
  end

  describe '#call incluye el uso del Drive' do
    before do
      drive_file(content_type: 'image/png', byte_size: 1_000)
      drive_file(content_type: 'video/mp4', byte_size: 20_000)
      drive_file(content_type: 'audio/mpeg', byte_size: 3_000)
      drive_file(content_type: 'application/pdf', byte_size: 5_000)
    end

    it 'suma el total del Drive al used_bytes del panel' do
      result = described_class.new(account).call
      expect(result[:used_bytes]).to eq(29_000)
    end

    it 'clasifica por categoría igual que el Drive' do
      by_type = described_class.new(account).call[:by_type]
      expect(by_type[:images][:bytes]).to eq(1_000)
      expect(by_type[:videos][:bytes]).to eq(20_000)
      expect(by_type[:audios][:bytes]).to eq(3_000)
      expect(by_type[:documents][:bytes]).to eq(5_000)
    end

    it 'calcula el porcentaje sobre la cuota del plan' do
      result = described_class.new(account).call
      # 29_000 bytes sobre 5 GiB es prácticamente 0 %, pero no nil.
      expect(result[:percent_used]).to be_a(Numeric)
      expect(result[:quota_bytes]).to eq(5 * 1.gigabyte)
    end
  end

  describe 'qué cuenta y qué no (papelera)' do
    it 'la papelera (soft delete, no purgado) SIGUE ocupando cuota' do
      drive_file(content_type: 'image/png', byte_size: 1_000)
      drive_file(content_type: 'image/png', byte_size: 500, deleted: true) # en papelera
      # 1500: lo activo + lo que está en la papelera (hasta que se purgue).
      expect(described_class.new(account).call[:used_bytes]).to eq(1_500)
    end

    it 'un archivo PURGADO ya NO cuenta' do
      drive_file(content_type: 'image/png', byte_size: 1_000)
      drive_file(content_type: 'image/png', byte_size: 9_999, purged: true)
      expect(described_class.new(account).call[:used_bytes]).to eq(1_000)
    end

    it 'expone cuántos bytes hay en la papelera (trash_bytes)' do
      drive_file(content_type: 'image/png', byte_size: 1_000)
      drive_file(content_type: 'image/png', byte_size: 500, deleted: true)
      expect(described_class.new(account).call[:trash_bytes]).to eq(500)
    end
  end

  describe 'Drive deshabilitado' do
    it 'no suma nada del Drive si el módulo está apagado' do
      # El criterio es feature_enabled?('jabvox_drive') (el mismo que usa el Drive),
      # no la columna cruda: el Drive está activo por defecto en toda cuenta.
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with('jabvox_drive').and_return(false)
      drive_file(content_type: 'image/png', byte_size: 1_000)
      expect(described_class.new(account).call[:used_bytes]).to eq(0)
    end
  end

  describe 'el Drive NO bloquea los adjuntos de mensajes (van a overflow)' do
    # storage_over_quota? valida la ADMISIÓN de adjuntos de mensajes. Si contara el
    # Drive, un Drive lleno rechazaría mensajes entrantes y se perdería información.
    # El Drive maneja el exceso con su propio bucket de overflow, no aquí.
    it 'un Drive lleno no hace que se rechace un adjunto de mensaje' do
      account.update!(limits: { 'storage_gb' => 1 })
      drive_file(content_type: 'application/zip', byte_size: 1.gigabyte - 10)
      # Aunque el Drive casi llena la cuota, admitir un adjunto de mensaje sigue OK.
      expect(account.storage_over_quota?(100)).to be(false)
    end

    it 'el panel (call) SÍ refleja el uso del Drive aunque la validación no' do
      account.update!(limits: { 'storage_gb' => 1 })
      drive_file(content_type: 'image/png', byte_size: 5_000)
      expect(described_class.new(account).call[:used_bytes]).to eq(5_000)
      expect(described_class.new(account).total_bytes).to eq(0)
    end
  end
end
