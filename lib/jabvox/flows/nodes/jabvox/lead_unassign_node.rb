# frozen_string_literal: true

# jabvox.lead.unassign — quita el agente asignado de uno o varios leads. No se
# tocan las conversaciones: no se le arranca a un agente un chat en curso.
class Jabvox::Flows::Nodes::Jabvox::LeadUnassignNode < Jabvox::Flows::Nodes::Jabvox::LeadAssignNode
  type 'jabvox.lead.unassign'
  label 'Desasignar Leads'

  def perform
    requested = requested_ids
    leads = account.jabvox_leads.where(id: requested).to_a
    account.jabvox_leads.where(id: leads.map(&:id)).update_all(assignee_id: nil) if leads.any? # rubocop:disable Rails/SkipsModelValidations
    bulk_result(requested, leads, 'unassigned')
  end

  private

  def empty_ids_message
    'Indica al menos un ID interno de lead para desasignar (campo "IDs internos de leads"). ' \
      'Van los IDs INTERNOS (campo `id` de la salida del nodo de búsqueda), no los números #N.'
  end
end
