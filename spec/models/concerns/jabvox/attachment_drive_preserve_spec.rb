# frozen_string_literal: true

require 'rails_helper'

# Al borrar un mensaje/conversación, el adjunto que YA está indexado en el Drive no
# debe perder su objeto físico: el blob se desvincula del adjunto SIN purgarse, para
# que el archivo del Drive siga existiendo y descargándose (antes daba 503/404).
RSpec.describe Jabvox::AttachmentDrivePreserve do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }

  def attachment_with_file
    att = message.attachments.new(account_id: account.id, file_type: :image)
    att.file.attach(io: StringIO.new('img'), filename: 'foto.jpg', content_type: 'image/jpeg')
    att.save!
    att
  end

  # Crea la fila del Drive que INDEXA el blob del adjunto (mismo object_key).
  def index_in_drive(att)
    account.jabvox_drive_files.create!(
      filename: 'foto.jpg', content_type: 'image/jpeg', byte_size: 3,
      object_key: att.file.blob.key, bucket: JabvoxDriveFile::BUCKET_PRIMARY, status: :available
    )
  end

  context 'cuando el blob está indexado por el Drive' do
    it 'al destruir el adjunto, el blob NO se purga (el objeto sobrevive)' do
      att = attachment_with_file
      index_in_drive(att)
      blob = att.file.blob

      expect { att.destroy! }.not_to(change { ActiveStorage::Blob.exists?(blob.id) })
      expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    end

    it 'desvincula el adjunto del blob (borra el join), pero deja la fila del Drive' do
      att = attachment_with_file
      drive_file = index_in_drive(att)
      blob = att.file.blob

      att.destroy!

      expect(ActiveStorage::Attachment.exists?(record_type: 'Attachment', record_id: att.id)).to be(false)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
      expect(JabvoxDriveFile.exists?(drive_file.id)).to be(true)
    end
  end

  context 'cuando el blob NO está indexado por el Drive' do
    it 'se comporta normal: el adjunto se destruye (no interferimos)' do
      att = attachment_with_file
      expect { att.destroy! }.not_to raise_error
    end
  end

  context 'con el feature jabvox_drive apagado' do
    it 'no interfiere con el borrado del adjunto' do
      att = attachment_with_file
      index_in_drive(att)
      allow(att).to receive(:account).and_return(account)
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with('jabvox_drive').and_return(false)
      expect { att.destroy! }.not_to raise_error
    end
  end
end
