# Expone la fecha en que se aplicó cada etiqueta a una conversación (dato que la API
# estándar de Chatwoot NO ofrece). Se apoya en jabvox_conversation_label_logs, que ya
# registra applied_at/removed_at de cada etiqueta.
#
# GET /api/v1/accounts/:account_id/jabvox/label_logs?label=detener-bot-masivo
#   Devuelve las conversaciones cuya etiqueta `label` sigue APLICADA (intervalo
#   abierto) con la fecha en que se aplicó y las horas transcurridas. NO decide nada
#   sobre umbrales de tiempo: solo informa. Quien consume (p. ej. n8n) decide si
#   quitarla a las 24h o el tiempo que sea.
class Api::V1::Accounts::Jabvox::LabelLogsController < Api::V1::Accounts::BaseController
  def index
    label = params[:label].to_s.strip
    return render(json: { error: 'Falta el parámetro label' }, status: :unprocessable_entity) if label.blank?

    now = Time.current
    logs = open_logs_for(label)

    render json: {
      label: label,
      now: now.iso8601,
      count: logs.size,
      data: logs.map { |log| serialize(log, now) }
    }
  end

  private

  # Intervalos abiertos (etiqueta aún puesta) de la cuenta actual para `label`.
  def open_logs_for(label)
    JabvoxConversationLabelLog.where(account_id: Current.account.id)
                              .for_label(label)
                              .open
                              .order(applied_at_jabvox: :asc)
                              .limit(result_limit)
  end

  def serialize(log, now)
    {
      conversation_id: log.conversation_id,
      label: log.label_jabvox,
      applied_at: log.applied_at_jabvox.iso8601,
      applied_at_epoch: log.applied_at_jabvox.to_i,
      hours_applied: ((now - log.applied_at_jabvox) / 3600.0).round(2)
    }
  end

  # Tope defensivo; el cliente pagina en lotes pequeños de todos modos.
  def result_limit
    limit = params[:limit].to_i
    limit.positive? ? [limit, 500].min : 200
  end
end
