# frozen_string_literal: true

# jabvox.lead.find_by_field — legacy (oculto): misma lógica que
# jabvox.lead.search modo by_field, con la salida original
# `{ field, operator, value, leads, count }`.
class Jabvox::Flows::Nodes::Jabvox::LeadFindByFieldNode < Jabvox::Flows::Nodes::Jabvox::LeadSearchNode
  type 'jabvox.contact.find_by_field'
  # Tipo anterior: los flujos guardados lo siguen usando.
  aliases 'jabvox.lead.find_by_field'
  label 'Buscar Contactos por campo'
  items_path 'leads'

  def perform
    found = by_field
    { 'field' => found['field'], 'operator' => found['operator'], 'value' => found['value'],
      'leads' => found['leads'], 'count' => found['count'] }
  end
end
