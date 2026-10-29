# frozen_string_literal: true

require 'rails_helper'

# El camino PRINCIPAL de ingesta: adjuntos entrantes de CUALQUIER bandeja conectada
# (no solo WhatsApp). Copia el blob de Active Storage al Drive.
RSpec.describe Jabvox::Drive::AttachmentIngestJob, :minio do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming) }

  before do
    skip 'MinIO no disponible' unless Jabvox::Drive::StorageService.configured? &&
                                      Jabvox::Drive::StorageService.new(account).available?
  end

  def build_incoming_attachment(filename: 'doc.pdf', content_type: 'application/pdf', file_type: :file)
    att = message.attachments.new(account_id: account.id, file_type: file_type)
    att.file.attach(io: StringIO.new('contenido de prueba'), filename: filename, content_type: content_type)
    att.save!
    att
  end

  it 'copia el adjunto entrante al Drive y crea la carpeta del contacto' do
    attachment = build_incoming_attachment
    operation = account.jabvox_drive_pending_operations.find_by(idempotency_key: "attachment-#{attachment.id}")
    expect(operation).to be_present # el concern registró la operación durable

    described_class.perform_now(account.id, attachment.id)

    operation.reload
    expect(operation).to be_completed
    drive_file = account.jabvox_drive_files.find_by(message_id: attachment.message_id)
    expect(drive_file).to be_present
    expect(drive_file).to be_available
    # queda en la carpeta contactos/<contacto>/<bandeja>/
    contact_slug = Jabvox::Drive::PathBuilder.contact_slug(contact)
    inbox_slug = Jabvox::Drive::PathBuilder.inbox_slug(attachment.message.conversation.inbox)
    expect(drive_file.folder&.path).to eq("/contactos/#{contact_slug}/#{inbox_slug}/")
    expect(drive_file.folder&.contact_id).to eq(contact.id)
    # el objeto está en MinIO bajo el prefijo de la cuenta
    svc = Jabvox::Drive::StorageService.new(account)
    expect(drive_file.object_key).to start_with(svc.account_prefix)
    expect(svc.head(drive_file.object_key)).to be_present

    svc.delete(drive_file.object_key)
  end

  it 'deja la operación pendiente si MinIO está caído (no pierde el adjunto)' do
    attachment = build_incoming_attachment
    operation = account.jabvox_drive_pending_operations.find_by(idempotency_key: "attachment-#{attachment.id}")
    allow_any_instance_of(Jabvox::Drive::StorageService).to receive(:available?).and_return(false)

    described_class.perform_now(account.id, attachment.id)

    expect(operation.reload).to be_pending
    expect(operation.last_error).to match(/MinIO/i)
  end
end
