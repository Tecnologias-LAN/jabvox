# frozen_string_literal: true

require 'rails_helper'

# Cubre los endurecimientos de seguridad de la ingesta entrante (OverflowService):
# validación de tamaño y detección de MIME real por magic bytes.
RSpec.describe Jabvox::Drive::OverflowService, :minio do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:service) { described_class.new(account) }

  before do
    skip 'MinIO no disponible' unless Jabvox::Drive::StorageService.configured? &&
                                      Jabvox::Drive::StorageService.new(account).available?
  end

  after do
    account.jabvox_drive_files.each do |f|
      Jabvox::Drive::StorageService.new(account).delete(f.object_key) rescue nil # rubocop:disable Style/RescueModifier
      Jabvox::Drive::StorageService.new(account).delete(f.object_key, bucket: 'overflow') rescue nil # rubocop:disable Style/RescueModifier
    end
  end

  describe 'MIME real (magic bytes)' do
    it 'ignora el content_type declarado y detecta el tipo real del contenido' do
      # Bytes de un GIF declarados como texto plano.
      file = service.ingest!(filename: 'truco.txt', content_type: 'text/plain',
                             bytes: "GIF89a\u0000\u0000contenido")
      expect(file.content_type).to eq('image/gif')
    end
  end

  describe 'límite de tamaño en ingesta entrante' do
    it 'rechaza un adjunto entrante que supera el máximo' do
      allow(described_class).to receive(:max_file_bytes).and_return(5)
      expect do
        service.ingest!(filename: 'grande.txt', content_type: 'text/plain', bytes: 'más de cinco bytes')
      end.to raise_error(described_class::FileTooLargeError)
    end

    it 'no deja reserva de cuota colgada al rechazar por tamaño' do
      allow(described_class).to receive(:max_file_bytes).and_return(5)
      quota = Jabvox::Drive::QuotaService.new(account)
      before_reserved = quota.reserved_bytes
      begin
        service.ingest!(filename: 'g.txt', content_type: 'text/plain', bytes: 'excede el limite')
      rescue described_class::FileTooLargeError
        # esperado
      end
      expect(Jabvox::Drive::QuotaService.new(account).reserved_bytes).to eq(before_reserved)
    end
  end
end
