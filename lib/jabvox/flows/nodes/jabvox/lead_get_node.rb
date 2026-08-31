# frozen_string_literal: true

# jabvox.lead.get — legacy (oculto): lo sustituye jabvox.lead.search modo
# "Por ID". Devuelve el detalle PLANO de UN lead por su PK interna.
class Jabvox::Flows::Nodes::Jabvox::LeadGetNode < Jabvox::Flows::Nodes::Jabvox::LeadSearchNode
  type 'jabvox.lead.get'
  label 'Obtener Lead'

  def perform
    lead_id = require_id!(param(:leadId), 'el ID interno del lead')
    lead = base_scope.find_by(id: lead_id)
    fail_with!(not_found_message(lead_id)) if lead.nil?

    slim(lead).merge('leadId' => lead.id, 'campaign_id' => lead.jabvox_campaign_id,
                     'assignee_id' => lead.assignee_id, 'is_sold' => lead.is_sold_jabvox)
  end

  private

  def not_found_message(lead_id)
    "El lead #{lead_id} no existe en esta cuenta. Comprueba que sea el ID INTERNO del lead " \
      '(campo `id` de la salida del nodo de búsqueda), no el número #N visible en Jabvox.'
  end
end
