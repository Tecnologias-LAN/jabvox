# Delivery/read/failed stats. Los CONTEOS salen de messages.status (Chatwoot
# guarda ahí el último estado de cada mensaje, con datos históricos completos);
# message_status_events solo se usa para los TIEMPOS (guarda el "cuándo" de cada
# transición) y puede estar vacía en cuentas anteriores a su despliegue.
#
# messages.status es acumulativo hacia atrás: un mensaje 'read' también fue
# entregado, así que delivered = (delivered + read).
module V2::Reports::WhatsappReport::MessageStatusStats
  # { 'delivered' => n, 'read' => n, 'failed' => n } sobre messages.status,
  # con delivered incluyendo los leídos.
  def status_event_counts
    @status_event_counts ||= begin
      raw = outgoing_messages.unscope(:order).group(:status).count
      read = raw['read'].to_i
      { 'delivered' => raw['delivered'].to_i + read, 'read' => read, 'failed' => raw['failed'].to_i }
    end
  end

  # Cuenta por agente desde messages.status (delivered incluye read).
  def agent_status_count(uid, status_name)
    scope = agent_outgoing(uid).unscope(:order)
    return scope.where(status: %i[delivered read]).count if status_name == 'delivered'

    scope.where(status: status_name).count
  end

  # Delivered/read/failed counts and rates for one agent's outgoing messages.
  def agent_delivery_stats(uid)
    sent = agent_outgoing(uid).count
    delivered = agent_status_count(uid, 'delivered')
    read = agent_status_count(uid, 'read')
    {
      delivered: delivered,
      read: read,
      failed: agent_outgoing(uid).unscope(:order).where(status: :failed).count,
      delivery_rate: rate(delivered, sent),
      read_rate: rate(read, delivered)
    }
  end

  # time-to-read of the customer: read.occurred_at − message.created_at, per
  # outgoing message the agent sent. Requires message_status_events (read).
  def customer_read_times(uid)
    elapsed_times_for('read', agent_outgoing(uid).select(:id))
  end

  # time-to-deliver: delivered.occurred_at − message.created_at, per agent message.
  def customer_delivery_times(uid)
    elapsed_times_for('delivered', agent_outgoing(uid).select(:id))
  end

  # Global (non-per-agent) elapsed times over all outgoing messages in scope.
  def all_read_times
    elapsed_times_for('read', outgoing_messages.select(:id))
  end

  def all_delivery_times
    elapsed_times_for('delivered', outgoing_messages.select(:id))
  end

  # Seconds between a message's created_at and its first `status` event, for every
  # message in the given id relation that reached that status.
  def elapsed_times_for(status, message_id_relation)
    events = MessageStatusEvent.where(account_id: account.id, status: MessageStatusEvent.statuses[status],
                                      message_id: message_id_relation)
                               .pluck(:message_id, :occurred_at)
    return [] if events.empty?

    created = account.messages.where(id: events.map(&:first)).pluck(:id, :created_at).to_h
    events.filter_map { |mid, at| (at - created[mid]).to_i if created[mid] }
  end

  def read_timestamp(message)
    MessageStatusEvent.where(message_id: message.id, status: MessageStatusEvent.statuses['read'])
                      .order(:occurred_at).first&.occurred_at
  end

  # Fallidos agrupados por el error de Meta guardado en
  # content_attributes.external_error de cada mensaje. Robusto: si un mensaje
  # fallido no trae error, cuenta como 'unknown'.
  def error_breakdown
    # content_attributes es columna json (no jsonb) y el acceso ->> es poco fiable
    # aquí; lo leemos vía el modelo (el hash siempre trae external_error).
    rows = outgoing_messages.unscope(:order).where(status: :failed)
                            .pluck(:content_attributes)
    rows.group_by { |attrs| (attrs.is_a?(Hash) ? attrs['external_error'] : nil).presence || 'unknown' }
        .map { |code, list| { code: code, count: list.size } }
        .sort_by { |r| -r[:count] }
  end
end
