# frozen_string_literal: true

# jabvox.lead.list — legacy (oculto): lo sustituye jabvox.lead.search modo
# "Listar todos". Conserva su salida original `{ leads, count }`.
class Jabvox::Flows::Nodes::Jabvox::LeadListNode < Jabvox::Flows::Nodes::Jabvox::LeadSearchNode
  type 'jabvox.contact.list'
  # Tipo anterior: los flujos guardados lo siguen usando.
  aliases 'jabvox.lead.list'
  label 'Listar Contactos'
  items_path 'leads'

  # Página de la lista original. Se conserva para que los flujos guardados que
  # paginaban sigan recorriendo los mismos tramos.
  PER_PAGE = 50

  def perform
    # Antes se usaba el scope `ordered` de JabvoxLead (por lead_number). Ese campo
    # desapareció con la tabla, así que el orden estable es por id, su equivalente.
    leads = filtered_scope.order(id: :asc).limit(PER_PAGE).offset((page - 1) * PER_PAGE).to_a
    { 'leads' => leads.map { |l| slim(l) }, 'count' => leads.length,
      'page' => page, 'truncated' => leads.length == PER_PAGE }
  end

  private

  def page
    @page ||= int_or(param(:page), 1, min: 1)
  end

  def filtered_scope
    scope = base_scope
    scope = scope.joins(:contact).where('contacts.name ILIKE ?', "%#{sanitized_query}%") if query.present?
    scope = scope.where(jabvox_campaign_id: param(:campaignId)) if param(:campaignId).present?
    scope = scope.where(assignee_id: param(:assigneeId)) if param(:assigneeId).present?
    scope
  end

  def query
    @query ||= param(:q).to_s.strip
  end

  def sanitized_query
    ActiveRecord::Base.sanitize_sql_like(query)
  end
end
