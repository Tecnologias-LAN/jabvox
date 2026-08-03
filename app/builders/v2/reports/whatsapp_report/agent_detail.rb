# Detalle por agente: la lista de mensajes salientes de un agente con su
# contacto/número, estado (enviado/entregado/leído/fallido), error de Meta si
# falló, plantilla y fecha. Respeta los filtros del reporte (fecha/bandeja/
# plantilla) porque parte de agent_outgoing (que usa el scope de conversaciones).
module V2::Reports::WhatsappReport::AgentDetail
  DETAIL_LIMIT = 5000

  # rows: una fila por mensaje. status_filter opcional (sent/delivered/read/failed).
  def agent_messages(uid, status_filter: nil)
    scope = agent_outgoing(uid).unscope(:order)
    scope = scope.where(status: status_filter) if valid_status?(status_filter)
    rows = scope.order(created_at: :desc).limit(DETAIL_LIMIT)
                .pluck(:id, :conversation_id, :status, :content, :created_at,
                       :content_attributes, :additional_attributes)
    contacts = contacts_for(rows.pluck(1))
    rows.map { |r| detail_row(r, contacts) }
  end

  # Conteo por estado para las pestañas del drill-down.
  def agent_status_summary(uid)
    counts = agent_outgoing(uid).unscope(:order).group(:status).count
    { sent: counts['sent'].to_i, delivered: counts['delivered'].to_i,
      read: counts['read'].to_i, failed: counts['failed'].to_i, total: counts.values.sum }
  end

  private

  def valid_status?(status)
    %w[sent delivered read failed].include?(status.to_s)
  end

  # { conversation_id => { name:, phone: } } en una query.
  def contacts_for(conversation_ids)
    ids = conversation_ids.compact.uniq
    return {} if ids.empty?

    account.conversations.where(id: ids).joins(:contact)
           .pluck('conversations.id', 'contacts.name', 'contacts.phone_number')
           .to_h { |cid, name, phone| [cid, { name: name, phone: phone }] }
  end

  def detail_row(row, contacts)
    id, conv_id, status, content, created_at, content_attrs, additional_attrs = row
    contact = contacts[conv_id] || {}
    {
      id: id,
      conversation_id: conv_id,
      name: contact[:name],
      phone: contact[:phone],
      status: status,
      template: additional_attrs.is_a?(Hash) ? additional_attrs.dig('template_params', 'name') : nil,
      error: content_attrs.is_a?(Hash) ? content_attrs['external_error'] : nil,
      content: content.to_s[0, 140],
      created_at: created_at&.iso8601
    }
  end
end
