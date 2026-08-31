# frozen_string_literal: true

# jabvox.conversation.send_message — publica un mensaje en la conversación.
# Con `private: true` es una NOTA PRIVADA: queda en el hilo para el equipo y no
# se envía al cliente.
class Jabvox::Flows::Nodes::Jabvox::ConversationSendMessageNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.conversation.send_message'
  label 'Enviar mensaje en conversación'

  def perform
    content = param(:content).to_s
    fail_with!('El mensaje no puede estar vacío.') if content.strip.blank?

    conversation = find_conversation!(param(:conversationId))
    private_note = opt_in?(param(:private))
    message = build_message(conversation, content, private_note)
    output(conversation, message, private_note)
  end

  private

  def build_message(conversation, content, private_note)
    conversation.messages.create!(
      account_id: account.id, inbox_id: conversation.inbox_id, content: content,
      message_type: :outgoing, private: private_note
    )
  end

  def output(conversation, message, private_note)
    { 'id' => message.id, 'conversation_id' => conversation.display_id,
      'content' => message.content, 'private' => private_note,
      'message_type' => message.message_type, 'status' => message.status,
      'created_at' => message.created_at.iso8601 }
  end
end
