# frozen_string_literal: true

require 'rails_helper'

# El adjunto de un mensaje cuya copia en el Drive está RETENIDA por falta de espacio
# (restricted) no debe exponer su URL: el payload lo marca storage_blocked para que el
# chat muestre "no se puede ver por falta de espacio". Al promoverse, vuelve a verse.
RSpec.describe Jabvox::AttachmentDriveState do
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

  # Crea la fila del Drive que INDEXA el blob del attachment, con el status dado.
  def index_drive_file(att, status:)
    account.jabvox_drive_files.create!(
      filename: 'foto.jpg', content_type: 'image/jpeg', byte_size: 3,
      object_key: att.file.blob.key, bucket: JabvoxDriveFile::BUCKET_PRIMARY,
      status: status
    )
  end

  context 'cuando el Drive retiene el adjunto por falta de espacio (restricted)' do
    it 'marca storage_blocked y oculta la URL en el payload' do
      att = attachment_with_file
      index_drive_file(att, status: :restricted)

      data = att.push_event_data
      expect(data[:storage_blocked]).to be(true)
      expect(data[:storage_state]).to eq('overflow')
      expect(data[:data_url]).to eq('')
      expect(data[:thumb_url]).to eq('')
    end
  end

  context 'cuando el adjunto está disponible (available)' do
    it 'expone la URL normal y NO marca storage_blocked' do
      att = attachment_with_file
      index_drive_file(att, status: :available)

      data = att.push_event_data
      expect(data[:storage_blocked]).to be_nil
      expect(data[:data_url]).to be_present
    end
  end

  context 'sin fila en el Drive (adjunto no indexado)' do
    it 'se comporta normal (no bloquea)' do
      att = attachment_with_file
      expect(att.push_event_data[:storage_blocked]).to be_nil
    end
  end

  context 'con el feature jabvox_drive apagado' do
    it 'nunca bloquea aunque exista una fila restricted' do
      att = attachment_with_file
      index_drive_file(att, status: :restricted)
      # El Drive está habilitado por defecto; simulamos el gating apagado.
      allow(att).to receive(:account).and_return(account)
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with('jabvox_drive').and_return(false)
      expect(att.push_event_data[:storage_blocked]).to be_nil
    end
  end

  it 'al promover (restricted -> available) el adjunto vuelve a mostrarse' do
    att = attachment_with_file
    drive_file = index_drive_file(att, status: :restricted)
    expect(att.push_event_data[:storage_blocked]).to be(true)

    drive_file.update!(status: :available)
    # Nueva instancia para evitar memoización del estado anterior.
    att_reloaded = Attachment.find(att.id)
    expect(att_reloaded.push_event_data[:storage_blocked]).to be_nil
    expect(att_reloaded.push_event_data[:data_url]).to be_present
  end
end
