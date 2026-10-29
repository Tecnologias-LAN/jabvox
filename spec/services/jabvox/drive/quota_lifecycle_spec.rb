# frozen_string_literal: true

require 'rails_helper'

# Ciclo de vida completo de la cuota (lo que pidió el usuario):
#   - al acabarse el espacio NO se pierde ningún dato (van a excedentes)
#   - al AUMENTAR la cuota, los excedentes se promueven y se VUELVEN VISIBLES
#   - al ELIMINAR, se liberan los contadores correctos (restricciones)
RSpec.describe 'Jabvox::Drive ciclo de cuota', :minio do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }

  before do
    skip 'MinIO no disponible' unless Jabvox::Drive::StorageService.configured? &&
                                      Jabvox::Drive::StorageService.new(account).available?
  end

  def force_quota(bytes)
    allow_any_instance_of(Jabvox::Drive::QuotaService).to receive(:quota_bytes).and_return(bytes)
  end

  after do
    account.jabvox_drive_files.each do |f|
      svc = Jabvox::Drive::StorageService.new(account)
      svc.delete(f.object_key) rescue nil # rubocop:disable Style/RescueModifier
      svc.delete(f.object_key, bucket: 'overflow') rescue nil # rubocop:disable Style/RescueModifier
    end
  end

  it 'cuando se acaba el espacio, NINGÚN dato se pierde (va a excedentes, restringido, no visible)' do
    force_quota(300) # muy pequeña
    svc = Jabvox::Drive::OverflowService.new(account)
    cabe = svc.ingest!(filename: 'a.txt', content_type: 'text/plain', bytes: 'x' * 100)      # cabe
    no_cabe = svc.ingest!(filename: 'b.txt', content_type: 'text/plain', bytes: 'y' * 400)   # no cabe

    expect(cabe).to be_available
    expect(no_cabe).to be_restricted
    expect(no_cabe.bucket).to eq('overflow')
    # el dato está guardado (no se perdió), solo que en cuarentena
    s = Jabvox::Drive::StorageService.new(account)
    expect(s.head(no_cabe.object_key, bucket: 'overflow')).to be_present
    # no visible en vistas normales
    expect(account.jabvox_drive_files.visible).to include(cabe)
    expect(account.jabvox_drive_files.visible).not_to include(no_cabe)
  end

  it 'al AUMENTAR la cuota, los excedentes se promueven y se vuelven visibles' do
    force_quota(100)
    svc = Jabvox::Drive::OverflowService.new(account)
    restringido = svc.ingest!(filename: 'c.txt', content_type: 'text/plain', bytes: 'z' * 300)
    expect(restringido).to be_restricted

    # el cliente amplía el plan -> cuota grande -> regularización
    force_quota(1_000_000)
    Jabvox::Drive::ReconciliationService.new(account).regularize!

    restringido.reload
    expect(restringido).to be_available           # ahora visible
    expect(restringido.bucket).to eq('primary')   # movido a principal
    s = Jabvox::Drive::StorageService.new(account)
    expect(s.head(restringido.object_key, bucket: 'primary')).to be_present
    expect(s.head(restringido.object_key, bucket: 'overflow')).to be_nil # origen borrado
    expect(account.jabvox_drive_files.visible).to include(restringido)
  end

  it 'la promoción de un excedente queda registrada en el historial (auditoría)' do
    force_quota(100)
    restringido = Jabvox::Drive::OverflowService.new(account).ingest!(
      filename: 'e.txt', content_type: 'text/plain', bytes: 'q' * 300
    )
    expect(restringido).to be_restricted
    force_quota(1_000_000)
    Jabvox::Drive::ReconciliationService.new(account).regularize!

    promote = account.jabvox_drive_audit_logs.for_action('promote').last
    expect(promote).to be_present
    expect(promote.auditable_id).to eq(restringido.id)
  end

  it 'si MinIO está caído al PURGAR, se encola un borrado durable (no deja huérfano)' do
    force_quota(1_000_000)
    file = Jabvox::Drive::OverflowService.new(account).ingest!(filename: 'f.txt', content_type: 'text/plain', bytes: 'w' * 100)
    fs = Jabvox::Drive::FileService.new(account)
    fs.destroy!(file) # a la papelera
    down = Jabvox::Drive::StorageService.new(account)
    allow(down).to receive(:delete).and_raise(Jabvox::Drive::StorageService::StorageUnavailableError)
    allow(fs).to receive(:storage).and_return(down)

    fs.purge!(file) # eliminar definitivamente con MinIO caído
    expect(file.reload.purged_at).to be_present # el usuario no se atasca
    op = account.jabvox_drive_pending_operations.find_by(kind: 'delete_object')
    expect(op).to be_present
    expect(op.payload['object_key']).to eq(file.object_key)

    Jabvox::Drive::StorageService.new(account).delete(file.object_key) rescue nil # rubocop:disable Style/RescueModifier
  end

  it 'enviar a papelera NO libera cuota; purgar SÍ la libera' do
    force_quota(1_000_000)
    file = Jabvox::Drive::OverflowService.new(account).ingest!(filename: 'd.txt', content_type: 'text/plain', bytes: 'w' * 500)
    allow_any_instance_of(Jabvox::Drive::QuotaService).to receive(:quota_bytes).and_return(1_000_000)
    expect(Jabvox::Drive::QuotaService.new(account).used_bytes).to eq(500)

    fs = Jabvox::Drive::FileService.new(account)
    fs.destroy!(file) # a la papelera
    expect(file.reload.in_trash?).to be(true)
    expect(Jabvox::Drive::QuotaService.new(account).used_bytes).to eq(500) # AÚN ocupa

    fs.purge!(file) # eliminar definitivamente
    expect(file.reload.purged?).to be(true)
    expect(Jabvox::Drive::QuotaService.new(account).used_bytes).to eq(0) # AHORA liberada
  end

  it 'al PURGAR y liberar espacio, encola la regularización para promover los excedentes' do
    # Cuota pequeña: un archivo llena el principal y el siguiente cae a overflow.
    force_quota(600)
    svc = Jabvox::Drive::OverflowService.new(account)
    grande = svc.ingest!(filename: 'g.txt', content_type: 'text/plain', bytes: 'a' * 500)
    excedente = svc.ingest!(filename: 'h.txt', content_type: 'text/plain', bytes: 'b' * 400)
    expect(grande).to be_available
    expect(excedente).to be_restricted # no cupo -> overflow

    fs = Jabvox::Drive::FileService.new(account)
    fs.destroy!(grande) # a la papelera (aún no libera)
    # Al PURGAR el grande se libera espacio: debe encolarse la regularización.
    expect(Jabvox::Drive::QuotaRegularizationJob).to receive(:perform_later).with(account.id)
    fs.purge!(grande)
  end

  it 'al PURGAR cuando NO hay excedentes, NO encola regularización (no malgasta jobs)' do
    force_quota(1_000_000)
    file = Jabvox::Drive::OverflowService.new(account).ingest!(
      filename: 'i.txt', content_type: 'text/plain', bytes: 'c' * 100
    )
    fs = Jabvox::Drive::FileService.new(account)
    fs.destroy!(file)
    expect(Jabvox::Drive::QuotaRegularizationJob).not_to receive(:perform_later)
    fs.purge!(file)
  end

  it 'ciclo COMPLETO end-to-end: lleno -> overflow -> PURGAR libera -> promueve -> visible' do
    force_quota(600)
    svc = Jabvox::Drive::OverflowService.new(account)
    grande = svc.ingest!(filename: 'big.txt', content_type: 'text/plain', bytes: 'a' * 500)
    excedente = svc.ingest!(filename: 'over.txt', content_type: 'text/plain', bytes: 'b' * 400)
    expect(excedente).to be_restricted

    fs = Jabvox::Drive::FileService.new(account)
    fs.destroy!(grande) # a la papelera: aún NO libera, el excedente sigue restricted
    expect(excedente.reload).to be_restricted

    # Al PURGAR el grande se liberan 500 bytes; la regularización promueve el excedente.
    perform_enqueued_jobs do
      fs.purge!(grande)
    end

    excedente.reload
    expect(excedente).to be_available         # YA visible
    expect(excedente.bucket).to eq('primary') # movido a principal
    expect(account.jabvox_drive_files.visible).to include(excedente)
  end

  it 'al promover un adjunto de mensaje dispara message.updated (refresco del chat en vivo)' do
    force_quota(100)
    inbox = create(:inbox, account: account)
    conversation = create(:conversation, account: account, inbox: inbox)
    message = create(:message, account: account, inbox: inbox, conversation: conversation)
    restringido = Jabvox::Drive::OverflowService.new(account).ingest!(
      filename: 'chat.txt', content_type: 'text/plain', bytes: 'z' * 300,
      message: message, conversation: conversation
    )
    expect(restringido).to be_restricted

    force_quota(1_000_000)
    # Al promover, debe emitirse message.updated para ESE mensaje (refresco en vivo).
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::MESSAGE_UPDATED, anything, hash_including(message: message))
      .at_least(:once)
    Jabvox::Drive::ReconciliationService.new(account).regularize!
  end
end
