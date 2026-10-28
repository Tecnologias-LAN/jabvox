# frozen_string_literal: true

# jabvox.conversation.add_private_note — añade una NOTA PRIVADA (interna) a la
# conversación: queda en el hilo para el equipo y NUNCA se envía al cliente.
#
# Es un nodo dedicado para no depender de acordarse de marcar `private` en
# "Enviar mensaje". Distinto de:
#  - jabvox.conversation.send_message (va al cliente por defecto),
#  - jabvox.note.create (nota en el CONTACTO, no en la conversación).
class Jabvox::Flows::Nodes::Jabvox::ConversationAddPrivateNoteNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.conversation.add_private_note'
  label 'Añadir nota privada a conversación'

  def perform
    content = param(:content).to_s
    fail_with!('La nota no puede estar vacía.') if content.strip.blank?

    conversation = find_conversation!(param(:conversationId))
    message = conversation.messages.create!(
      account_id: account.id, inbox_id: conversation.inbox_id, content: content,
      message_type: :outgoing, private: true
    )
    { 'id' => message.id, 'conversation_id' => conversation.display_id,
      'content' => message.content, 'private' => true,
      'created_at' => message.created_at.iso8601 }
  end
end
