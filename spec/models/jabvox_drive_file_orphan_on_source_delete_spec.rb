# frozen_string_literal: true

require 'rails_helper'

# Regla de negocio: los archivos del Drive SOBREVIVEN al borrado de su conversación,
# contacto o mensaje de origen. El archivo queda normal en el Drive (su objeto en
# MinIO, su carpeta y su cuota NO se tocan); solo se borra a mano desde la papelera.
#
# Antes, los FK a conversations/contacts/messages eran RESTRICT y el DELETE de la
# conversación fallaba con InvalidForeignKey (la conversación "no se eliminaba"
# aunque el frontend dijera "eliminada con éxito"). Ahora son ON DELETE SET NULL.
RSpec.describe 'JabvoxDriveFile: huérfano al borrar el origen', type: :model do
  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }

  def drive_file(message: nil, conversation: nil, contact: nil)
    account.jabvox_drive_files.create!(
      filename: 'foto.jpg', content_type: 'image/jpeg', byte_size: 10,
      object_key: "acct-#{account.id}/contactos/x/#{SecureRandom.hex(6)}",
      bucket: JabvoxDriveFile::BUCKET_PRIMARY, status: :available,
      message: message, conversation: conversation, contact: contact
    )
  end

  it 'borrar la CONVERSACIÓN no falla y el archivo sobrevive (referencias en NULL)' do
    file = drive_file(message: message, conversation: conversation, contact: contact)

    expect { conversation.destroy! }.not_to raise_error

    file.reload
    expect(file).to be_persisted              # el archivo sigue en el Drive
    expect(file.status).to eq('available')    # sigue visible, no se envió a papelera
    expect(file.conversation_id).to be_nil    # huérfano de la conversación
    expect(file.object_key).to be_present      # el objeto en MinIO no se tocó
  end

  # Los mensajes de la conversación se borran async (dependent: :destroy_async). Al
  # borrarse cada mensaje, el FK ON DELETE SET NULL deja el archivo huérfano del
  # mensaje pero intacto. Simulamos ese borrado del mensaje directamente.
  it 'borrar el MENSAJE de origen deja message_id en NULL y el archivo sobrevive' do
    file = drive_file(message: message, conversation: conversation, contact: contact)

    expect { message.destroy! }.not_to raise_error

    file.reload
    expect(file).to be_persisted
    expect(file.message_id).to be_nil
    expect(file.status).to eq('available')
  end

  it 'borrar el CONTACTO no falla y el archivo sobrevive (contact_id en NULL)' do
    file = drive_file(contact: contact)

    expect { contact.destroy! }.not_to raise_error

    file.reload
    expect(file).to be_persisted
    expect(file.contact_id).to be_nil
    expect(file.status).to eq('available')
  end

  it 'el archivo NO se envía a la papelera al borrar el origen (deleted_at sigue nil)' do
    file = drive_file(conversation: conversation)
    conversation.destroy!
    expect(file.reload.deleted_at).to be_nil
  end
end
