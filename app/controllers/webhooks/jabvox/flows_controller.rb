# frozen_string_literal: true

# Punto de entrada PÚBLICO para el disparador "Webhook entrante" (trigger.webhook)
# de las Automatizaciones avanzadas. Un sistema externo hace POST (o el método que
# el nodo permita) a la URL única del flujo:
#
#   POST /webhooks/jabvox/flows/:token
#
# El `:token` (JabvoxFlow#webhook_token) resuelve el flujo y su cuenta. El nodo
# trigger.webhook puede además exigir un `secret` (header X-Jabvox-Flow-Secret o
# query ?secret=) que se compara timing-safe. El body/query/headers quedan en
# `{{trigger.body/query/headers}}` dentro del flujo.
#
# Endpoint sin sesión (ActionController::API): la autorización es el token + el
# secreto opcional del nodo, nunca una cookie de usuario.
class Webhooks::Jabvox::FlowsController < ActionController::API
  WEBHOOK_TRIGGER_TYPE = 'trigger.webhook'

  def trigger
    flow = JabvoxFlow.active.find_by(webhook_token: params[:token])
    return render_not_found if flow.nil?
    return render_feature_off unless flow.account&.feature_enabled?('jabvox_advanced_automations')

    version = flow.current_version
    return render_error('El flujo no tiene un grafo publicado.', :unprocessable_entity) if version.nil?

    node = matching_webhook_node(version)
    return render_error('Ningún webhook de este flujo acepta esta petición.', :forbidden) if node.nil?

    enqueue_run(flow, version, node)
    render json: { ok: true, status: 'queued' }, status: :accepted
  end

  private

  # Payload que verá el flujo: lo que el nodo trigger.webhook promete en su UI.
  def webhook_payload
    {
      'method' => request.request_method,
      'secret' => provided_secret,
      'body' => request_body,
      'query' => request.query_parameters,
      'headers' => safe_headers
    }
  end

  def matching_webhook_node(version)
    payload = webhook_payload
    version.engine_graph.nodes.find do |node|
      node.type == WEBHOOK_TRIGGER_TYPE &&
        !node.disabled? &&
        Jabvox::Flows::Nodes::Triggers::WebhookNode.matches?(node, payload)
    end
  end

  def enqueue_run(flow, version, node)
    run = JabvoxFlowRun.create!(
      account_id: flow.account_id, flow: flow, version: version,
      status: :pending, trigger: webhook_payload.merge('type' => WEBHOOK_TRIGGER_TYPE), triggered_by: nil
    )
    Jabvox::Flows::RunJob.perform_later(run.id, trigger_type: WEBHOOK_TRIGGER_TYPE, trigger_node_id: node.id)
  end

  def provided_secret
    request.headers['X-Jabvox-Flow-Secret'].presence || params[:secret].to_s
  end

  def request_body
    raw = request.request_parameters
    return raw if raw.present?

    # Body no-form (JSON crudo u otro): se expone tal cual como texto.
    request.body.rewind
    request.body.read
  rescue StandardError
    {}
  end

  # No se exponen todas las cabeceras (traen tokens/cookies). Solo las de uso común
  # en integraciones, en minúsculas.
  def safe_headers
    allowed = %w[content-type user-agent x-request-id x-forwarded-for accept]
    allowed.index_with { |h| request.headers[h] }.compact
  end

  def render_not_found
    render json: { ok: false, error: 'Webhook no encontrado.' }, status: :not_found
  end

  def render_feature_off
    render json: { ok: false, error: 'El módulo de automatizaciones avanzadas no está activo.' }, status: :forbidden
  end

  def render_error(message, status)
    render json: { ok: false, error: message }, status: status
  end
end
