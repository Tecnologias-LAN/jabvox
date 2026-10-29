# frozen_string_literal: true

require 'rails_helper'

# Red de seguridad del SYNC del Drive (regresión del caso real 42/43/44):
# un adjunto se subió a MinIO vía Active Storage pero NUNCA creó su fila en el Drive
# (el enganche after_create_commit no corrió: deploy a medias / worker sin la clase
# recargada / feature flag apagado en ese instante), y por eso tampoco quedó una
# operación durable que reintentar. ReconciliationService#reconcile! debe DETECTARLO
# y reencolar su ingesta, sin intervención manual.
RSpec.describe Jabvox::Drive::ReconciliationService, '#reconcile! reindex de huérfanos' do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }

  before do
    # Aislar de MinIO: las otras fases de reconcile! (objetos faltantes/huérfanos) no
    # deben tocar el almacenamiento en este test. Solo nos interesa el reindexado.
    storage = instance_double(Jabvox::Drive::StorageService)
    allow(Jabvox::Drive::StorageService).to receive(:new).and_return(storage)
    allow(storage).to receive(:head).and_return({ key: 'x' }) # objetos "existen"
    allow(storage).to receive(:list).and_return([])           # sin huérfanos físicos
    allow_any_instance_of(Jabvox::Drive::QuotaService).to receive(:recalculate!)
    allow_any_instance_of(Jabvox::Drive::QuotaService).to receive(:storage_account)
      .and_return(instance_double(JabvoxDriveStorageAccount, update!: true))
  end

  # Crea un adjunto de mensaje con blob, SIN su fila en el Drive (huérfano).
  def orphan_attachment
    att = message.attachments.new(account_id: account.id, file_type: :image)
    att.file.attach(io: StringIO.new('img'), filename: 'foto.jpg', content_type: 'image/jpeg')
    att.save!
    att
  end

  it 'reencola AttachmentIngestJob para el adjunto que está en MinIO pero sin fila' do
    att = orphan_attachment

    expect(Jabvox::Drive::AttachmentIngestJob).to receive(:perform_later).with(account.id, att.id)

    result = described_class.new(account).reconcile!
    expect(result[:reindexed_attachments]).to eq(1)
  end

  it 'NO reencola si el adjunto YA tiene fila en el Drive (idempotente)' do
    att = orphan_attachment
    account.jabvox_drive_files.create!(
      filename: 'foto.jpg', content_type: 'image/jpeg', byte_size: 3,
      object_key: att.file.blob.key, bucket: JabvoxDriveFile::BUCKET_PRIMARY, status: :available
    )

    expect(Jabvox::Drive::AttachmentIngestJob).not_to receive(:perform_later)

    result = described_class.new(account).reconcile!
    expect(result[:reindexed_attachments]).to eq(0)
  end

  it 'NO reencola si el adjunto está en la PAPELERA (respeta el borrado del usuario)' do
    att = orphan_attachment
    account.jabvox_drive_files.create!(
      filename: 'foto.jpg', content_type: 'image/jpeg', byte_size: 3,
      object_key: att.file.blob.key, bucket: JabvoxDriveFile::BUCKET_PRIMARY,
      status: :available, deleted_at: Time.current
    )

    expect(Jabvox::Drive::AttachmentIngestJob).not_to receive(:perform_later)

    described_class.new(account).reconcile!
  end

  it 'con el feature apagado, no reindexa nada' do
    orphan_attachment
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('jabvox_drive').and_return(false)

    expect(Jabvox::Drive::AttachmentIngestJob).not_to receive(:perform_later)

    result = described_class.new(account).reconcile!
    expect(result[:reindexed_attachments]).to eq(0)
  end
end
