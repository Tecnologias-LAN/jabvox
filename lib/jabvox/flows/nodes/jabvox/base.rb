# frozen_string_literal: true

# Base de los nodos `jabvox.*`. Resuelve las entidades SIEMPRE dentro de la
# cuenta del run: multi-tenant estricto, un id de otra cuenta es "no existe".
class Jabvox::Flows::Nodes::Jabvox::Base < Jabvox::Flows::Nodes::Base
  private

  # Conversación por su display_id (el que se ve en la URL y usan los flujos).
  def find_conversation!(raw, label = 'el ID de la conversación')
    display_id = require_id!(raw, label)
    conversation = account.conversations.find_by(display_id: display_id)
    return conversation if conversation

    fail_with!("La conversación #{display_id} no existe en esta cuenta (puede haberse borrado). " \
               'Comprueba el ID; si viene de un paso anterior, revisa que ese paso siga devolviéndola.')
  end

  def find_contact!(raw, label = 'el ID interno del contacto')
    contact_id = require_id!(raw, label)
    contact = account.contacts.find_by(id: contact_id)
    return contact if contact

    fail_with!("El contacto #{contact_id} no existe en esta cuenta. Comprueba que sea el ID INTERNO " \
               'del contacto (no el número de lead).')
  end

  def find_lead!(raw, label = 'el ID del lead')
    lead_id = require_id!(raw, label)
    lead = account.jabvox_leads.find_by(id: lead_id)
    return lead if lead

    fail_with!("El lead #{lead_id} no existe en esta cuenta.")
  end

  def find_inbox!(raw, label = 'la bandeja')
    inbox_id = require_id!(raw, label)
    inbox = account.inboxes.find_by(id: inbox_id)
    return inbox if inbox

    fail_with!("La bandeja #{inbox_id} no existe en esta cuenta.")
  end

  # Vista compacta de un contacto para la salida de los nodos.
  def contact_view(contact)
    return nil if contact.nil?

    { 'id' => contact.id, 'name' => contact.name, 'email' => contact.email,
      'phone_number' => contact.phone_number, 'identifier' => contact.identifier }
  end
end
