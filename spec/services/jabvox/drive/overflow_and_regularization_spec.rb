# frozen_string_literal: true

require 'rails_helper'

# Integración end-to-end del flujo de EXCEDENTES (cuota llena) y su REGULARIZACIÓN
# al ampliar la cuota. Corre contra el MinIO real (marcada :minio) porque el valor
# de la prueba está en verificar el movimiento real de objetos entre buckets.
RSpec.describe 'Jabvox::Drive overflow y regularización', :minio do
  let(:account) { create(:account) }

  before do
    skip 'MinIO no disponible' unless Jabvox::Drive::StorageService.configured? &&
                                      Jabvox::Drive::StorageService.new(account).available?
  end

  # Fuerza una cuota finita pequeña sin depender del plan.
  def force_quota(bytes)
    allow_any_instance_of(Jabvox::Drive::QuotaService).to receive(:quota_bytes).and_return(bytes)
  end

  it 'desvía a overflow cuando no cabe y lo restaura al ampliar la cuota' do
    # Cuota 10 bytes: un archivo de 26 bytes NO cabe -> overflow.
    force_quota(10)
    file = Jabvox::Drive::OverflowService.new(account).ingest!(
      filename: 'grande.txt',
      content_type: 'text/plain',
      bytes: 'contenido de 26 bytes aqui'
    )

    expect(file).to be_restricted
    expect(file.bucket).to eq(JabvoxDriveFile::BUCKET_OVERFLOW)
    # El objeto está realmente en el bucket de excedentes.
    svc = Jabvox::Drive::StorageService.new(account)
    expect(svc.head(file.object_key, bucket: Jabvox::Drive::StorageService::OVERFLOW)).to be_present
    # No visible en las vistas normales.
    expect(account.jabvox_drive_files.visible).not_to include(file)

    # Ampliamos la cuota y regularizamos.
    force_quota(1_000_000)
    Jabvox::Drive::ReconciliationService.new(account).regularize!

    file.reload
    expect(file).to be_available
    expect(file.bucket).to eq(JabvoxDriveFile::BUCKET_PRIMARY)
    # El objeto se copió a primary y se borró de overflow.
    expect(svc.head(file.object_key, bucket: Jabvox::Drive::StorageService::PRIMARY)).to be_present
    expect(svc.head(file.object_key, bucket: Jabvox::Drive::StorageService::OVERFLOW)).to be_nil
    # Ahora sí es visible.
    expect(account.jabvox_drive_files.visible).to include(file)

    # limpieza
    svc.delete(file.object_key, bucket: Jabvox::Drive::StorageService::PRIMARY)
  end

  it 'es idempotente por sha256 (no doble-cuenta ni re-sube)' do
    force_quota(1_000_000)
    svc = Jabvox::Drive::OverflowService.new(account)
    f1 = svc.ingest!(filename: 'a.txt', content_type: 'text/plain', bytes: 'mismos bytes')
    f2 = svc.ingest!(filename: 'b.txt', content_type: 'text/plain', bytes: 'mismos bytes')
    expect(f2.id).to eq(f1.id)
    expect(account.jabvox_drive_files.where(sha256: f1.sha256).count).to eq(1)

    Jabvox::Drive::StorageService.new(account).delete(f1.object_key)
  end

  describe 'index_blob! (Drive indexa un objeto ya en MinIO, sin re-copiar)' do
    let(:storage) { Jabvox::Drive::StorageService.new(account) }

    # Sube un objeto directamente al bucket primary bajo el prefijo de la cuenta,
    # imitando el blob de Active Storage de un adjunto (acct/conversaciones/...).
    def put_conversation_object(bytes)
      rel = "conversaciones/conversacion-1/#{SecureRandom.hex(8)}.txt"
      res = storage.put(rel, bytes, content_type: 'text/plain', bucket: Jabvox::Drive::StorageService::PRIMARY)
      res[:key]
    end

    it 'crea una fila que APUNTA a la misma object_key (una sola copia física)' do
      force_quota(1_000_000)
      key = put_conversation_object('hola adjunto')
      file = Jabvox::Drive::OverflowService.new(account).index_blob!(
        object_key: key, filename: 'foto.jpg', content_type: 'image/jpeg', byte_size: 12
      )
      expect(file.object_key).to eq(key)        # misma key, no se copió
      expect(file).to be_available
      expect(file.bucket).to eq(JabvoxDriveFile::BUCKET_PRIMARY)
      # No se creó ningún objeto nuevo bajo files/: el objeto sigue siendo el mismo.
      expect(storage.head(key, bucket: Jabvox::Drive::StorageService::PRIMARY)).to be_present

      storage.delete(key)
    end

    it 'es idempotente: indexar la misma key dos veces no duplica fila' do
      force_quota(1_000_000)
      key = put_conversation_object('contenido')
      svc = Jabvox::Drive::OverflowService.new(account)
      a = svc.index_blob!(object_key: key, filename: 'a.txt', content_type: 'text/plain', byte_size: 9)
      b = svc.index_blob!(object_key: key, filename: 'a.txt', content_type: 'text/plain', byte_size: 9)
      expect(b.id).to eq(a.id)
      expect(account.jabvox_drive_files.where(object_key: key).count).to eq(1)

      storage.delete(key)
    end

    it 'rechaza indexar una key de OTRA cuenta (aislamiento)' do
      key_ajena = "acct-#{account.id + 999}/conversaciones/conversacion-1/x.txt"
      expect do
        Jabvox::Drive::OverflowService.new(account).index_blob!(
          object_key: key_ajena, filename: 'x.txt', content_type: 'text/plain', byte_size: 1
        )
      end.to raise_error(Jabvox::Drive::StorageService::InvalidKeyError)
    end

    it 'si la cuota está llena, el indexado queda restricted y se promueve al liberar' do
      force_quota(5) # diminuta
      key = put_conversation_object('doce bytes!!')
      file = Jabvox::Drive::OverflowService.new(account).index_blob!(
        object_key: key, filename: 'f.txt', content_type: 'text/plain', byte_size: 12
      )
      expect(file).to be_restricted
      expect(file.bucket).to eq(JabvoxDriveFile::BUCKET_PRIMARY) # el objeto NO se movió

      # Al ampliar la cuota, se promueve sin mover el objeto (solo cambia status).
      force_quota(1_000_000)
      Jabvox::Drive::ReconciliationService.new(account).regularize!
      file.reload
      expect(file).to be_available
      expect(file.object_key).to eq(key) # sigue en su sitio

      storage.delete(key)
    end
  end
end
