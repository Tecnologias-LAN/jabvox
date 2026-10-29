# frozen_string_literal: true

require 'rails_helper'

# Verifica que, con Active Storage en MinIO/S3 y el módulo jabvox-drive activo, los
# adjuntos de mensajes se guardan bajo una ruta por cuenta y conversación:
#   acct-<account_id>/conversaciones/conversacion-<conversation_id>/<token><ext>
# y que el comportamiento es ADITIVO y seguro (no rompe nada cuando no aplica).
RSpec.describe Jabvox::AttachmentDriveStorageKey do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }

  def build_attachment
    att = message.attachments.new(account_id: account.id, file_type: :image)
    att.file.attach(io: StringIO.new('img'), filename: 'foto.jpg', content_type: 'image/jpeg')
    att
  end

  context 'cuando Active Storage usa S3/MinIO y el Drive está activo' do
    before do
      # En test AS usa Disk; simulamos que el servicio es S3 para ejercitar la lógica.
      allow_any_instance_of(described_class).to receive(:jabvox_drive_s3_service?).and_return(true)
    end

    it 'guarda el adjunto bajo acct-<id>/contactos/<contacto>/<bandeja>/' do
      att = build_attachment
      att.save!
      key = att.file.blob.key
      contact_slug = Jabvox::Drive::PathBuilder.contact_slug(conversation.contact)
      inbox_slug = Jabvox::Drive::PathBuilder.inbox_slug(inbox)
      expect(key).to start_with("acct-#{account.id}/contactos/#{contact_slug}/#{inbox_slug}/")
    end

    it 'conserva la extensión del archivo en la key' do
      att = build_attachment
      att.save!
      expect(att.file.blob.key).to end_with('.jpg')
    end

    it 'cada adjunto del MISMO contacto+bandeja comparte el prefijo' do
      a1 = build_attachment
      a1.save!
      msg2 = create(:message, account: account, inbox: inbox, conversation: conversation)
      a2 = msg2.attachments.new(account_id: account.id, file_type: :image)
      a2.file.attach(io: StringIO.new('img2'), filename: 'otra.png', content_type: 'image/png')
      a2.save!

      contact_slug = Jabvox::Drive::PathBuilder.contact_slug(conversation.contact)
      prefix = "acct-#{account.id}/contactos/#{contact_slug}/#{Jabvox::Drive::PathBuilder.inbox_slug(inbox)}/"
      expect(a1.file.blob.key).to start_with(prefix)
      expect(a2.file.blob.key).to start_with(prefix)
      expect(a1.file.blob.key).not_to eq(a2.file.blob.key) # token único por archivo
    end
  end

  context 'cuando NO aplica (comportamiento aditivo/seguro)' do
    it 'con el Drive DESACTIVADO deja la key plana por defecto' do
      allow_any_instance_of(described_class).to receive(:jabvox_drive_s3_service?).and_return(true)
      account.update!(jabvox_drive_enabled_jabvox: false)
      att = build_attachment
      att.save!
      expect(att.file.blob.key).not_to include('contactos')
    end

    it 'con Active Storage en disco local (no S3) deja la key plana' do
      # jabvox_drive_s3_service? devuelve false en test (Disk) por defecto.
      att = build_attachment
      att.save!
      expect(att.file.blob.key).not_to include('contactos')
    end
  end
end
