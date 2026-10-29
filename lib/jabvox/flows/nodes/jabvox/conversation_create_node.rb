# frozen_string_literal: true

# jabvox.conversation.create — abre una conversación para un contacto en una
# bandeja. Devuelve `conversationId` = display_id, que es el que consumen los
# demás nodos de conversación (NO el id interno).
class Jabvox::Flows::Nodes::Jabvox::ConversationCreateNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.conversation.create'
  label 'Crear conversación'

  STATUSES = Conversation.statuses.keys.freeze

  def perform
    inbox = find_inbox!(param(:inboxId), 'la "Bandeja"')
    contact = find_contact!(param(:contactId))
    conversation = create_conversation(inbox, contact)
    message = create_initial_message(conversation)
    output(conversation, message)
  end

  private

  def create_conversation(inbox, contact)
    attrs = { inbox_id: inbox.id, contact_id: contact.id,
              contact_inbox_id: contact_inbox(inbox, contact).id, status: status }
    attrs[:assignee_id] = assignee.id if assignee
    attrs[:team_id] = team.id if team
    account.conversations.create!(attrs)
  end

  # Sin ContactInbox no hay conversación. El builder genera el source_id que
  # toca según el canal cuando no se indica uno.
  def contact_inbox(inbox, contact)
    ContactInboxBuilder.new(contact: contact, inbox: inbox,
                            source_id: first_filled(param(:sourceId)).presence).perform
  rescue ActionController::ParameterMissing, RuntimeError => e
    fail_with!("No se pudo abrir la conversación en la bandeja #{inbox.id} (#{inbox.name}): #{e.message}. " \
               'Rellena el "Source ID" del paso o completa el teléfono/email del contacto.')
  end

  def status
    value = first_filled(param(:status), 'open')
    return value if STATUSES.include?(value)

    fail_with!("\"#{value}\" no es un estado válido para nacer la conversación. Usa uno de: #{STATUSES.join(', ')}.")
  end

  # Agente y equipo se validan DENTRO de la cuenta: un id ajeno o inexistente
  # corta el paso en vez de crear la conversación sin asignar.
  def assignee
    @assignee ||= begin
      raw = first_filled(param(:assigneeId))
      raw.blank? ? nil : find_agent!(raw)
    end
  end

  def team
    @team ||= begin
      raw = first_filled(param(:teamId))
      raw.blank? ? nil : find_team!(raw)
    end
  end

  def find_agent!(raw)
    agent = account.users.find_by(id: raw)
    return agent if agent

    fail_with!("El agente #{raw} no existe en esta cuenta. Elige un agente de la lista del paso.")
  end

  def find_team!(raw)
    found = account.teams.find_by(id: raw)
    return found if found

    fail_with!("El equipo #{raw} no existe en esta cuenta. Elige un equipo de la lista del paso.")
  end

  def create_initial_message(conversation)
    content = param(:message).to_s
    return nil if content.strip.blank?

    conversation.messages.create!(account_id: account.id, inbox_id: conversation.inbox_id,
                                  content: content, message_type: :outgoing, private: false)
  end

  def output(conversation, message)
    { 'conversationId' => conversation.display_id, 'id' => conversation.display_id,
      'internal_id' => conversation.id, 'inbox_id' => conversation.inbox_id,
      'contact_id' => conversation.contact_id, 'contact_inbox_id' => conversation.contact_inbox_id,
      'source_id' => conversation.contact_inbox.source_id, 'status' => conversation.status,
      'assignee_id' => conversation.assignee_id, 'team_id' => conversation.team_id,
      'message_id' => message&.id, 'created_at' => conversation.created_at.iso8601 }
  end
end
