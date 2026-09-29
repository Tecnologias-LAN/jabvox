# frozen_string_literal: true

# jabvox.lead.assign — asigna uno o varios leads a un agente. El endpoint
# original ignoraba en silencio los ids inexistentes: aquí se comparan los
# pedidos con los realmente afectados y se publican los que faltan.
class Jabvox::Flows::Nodes::Jabvox::LeadAssignNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.contact.assign'
  # Tipo anterior: los flujos guardados lo siguen usando.
  aliases 'jabvox.lead.assign'
  label 'Asignar Contactos'

  def perform
    requested = requested_ids
    assignee = find_assignee!
    leads = account.contacts.where(id: requested).to_a
    apply(leads, assignee)
    bulk_result(requested, leads, 'assigned')
  end

  private

  def apply(leads, assignee)
    return if leads.empty?

    account.contacts.where(id: leads.map(&:id)).update_all(assignee_id: assignee.id) # rubocop:disable Rails/SkipsModelValidations
    # Las conversaciones abiertas del contacto siguen al dueño del lead.
    Jabvox::ContactConversationAssignmentSync.new(account).sync_contacts(leads, assignee)
  end

  def find_assignee!
    assignee_id = require_id!(param(:assigneeId), 'el agente a asignar')
    assignee = account.users.find_by(id: assignee_id)
    return assignee if assignee

    fail_with!("El agente #{assignee_id} no pertenece a esta cuenta. Elige un agente de la cuenta " \
               'en el campo "Agente".')
  end

  # IDs pedidos, sin repetidos y ya como enteros comparables con los de la BD.
  def requested_ids
    ids = str_list(param(:leadIds)).map(&:to_i).uniq.reject(&:zero?)
    fail_with!(empty_ids_message) if ids.empty?

    ids
  end

  def empty_ids_message
    'Indica al menos un ID interno de lead para asignar (campo "IDs internos de leads"). ' \
      'Van los IDs INTERNOS (campo `id` de la salida del nodo de búsqueda), no los números #N.'
  end

  # Se publican los ids que NO existían: el endpoint original solo devolvía
  # cuántos había afectado, así que un id erróneo pasaba desapercibido.
  def bulk_result(requested, leads, key)
    found = leads.map(&:id)
    missing = requested - found
    { key => found.length, 'requested' => requested.length,
      'leadIds' => requested, 'missingIds' => missing,
      'notFound' => missing.length }.merge(missing.empty? ? {} : { 'warning' => warning(requested, found, missing) })
  end

  def warning(requested, found, missing)
    "Se pidieron #{requested.length} leads y solo se afectaron #{found.length}: " \
      "#{missing.length} id(s) no existen en esta cuenta (#{missing.join(', ')}). " \
      'Recuerda que aquí van los IDs INTERNOS, no los números #N.'
  end
end
