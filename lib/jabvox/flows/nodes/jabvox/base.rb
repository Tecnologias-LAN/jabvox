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
               'del contacto.')
  end

  # Se conserva el nombre porque lo usan nodos y flujos guardados, pero lo que resuelve es
  # un CONTACTO: es lo único que queda tras retirar Leads.
  def find_lead!(raw, label = 'el ID del contacto')
    contact_id = require_id!(raw, label)
    contact = account.contacts.find_by(id: contact_id)
    return contact if contact

    fail_with!("El contacto #{contact_id} no existe en esta cuenta.")
  end

  def find_inbox!(raw, label = 'la bandeja')
    inbox_id = require_id!(raw, label)
    inbox = account.inboxes.find_by(id: inbox_id)
    return inbox if inbox

    fail_with!("La bandeja #{inbox_id} no existe en esta cuenta.")
  end

  # Vista de un contacto para la salida de los nodos. Las cinco primeras claves
  # son el contrato HISTÓRICO (los flujos guardados las referencian y no cambian).
  # El resto se añadió para que la búsqueda/listado traiga la ficha COMPLETA:
  # atributos personalizados (los de Chatwoot y los de Jabvox) y la empresa.
  def contact_view(contact)
    return nil if contact.nil?

    { 'id' => contact.id, 'name' => contact.name, 'email' => contact.email,
      'phone_number' => contact.phone_number, 'identifier' => contact.identifier,
      'custom_attributes' => contact.custom_attributes || {},
      'additional_attributes' => contact.additional_attributes || {},
      'custom_fields_jabvox' => contact.custom_fields_jabvox || {},
      'company' => company_view(contact) }
  end

  # Empresa asociada al contacto. Solo cuando el módulo de empresas está activo
  # (la asociación vive en enterprise); si no, `nil` en vez de levantar la relación.
  def company_view(contact)
    return nil unless account.feature_enabled?('companies')

    company = contact.company
    return nil if company.nil?

    { 'id' => company.id, 'name' => company.name,
      'nit' => company.additional_attributes&.dig('nit') }
  end
end
