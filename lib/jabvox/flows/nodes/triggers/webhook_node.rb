# frozen_string_literal: true

# trigger.webhook — dispara al recibir una petición en la URL única del flujo.
# El body queda en `{{trigger.body.*}}`, con `{{trigger.query.*}}` y
# `{{trigger.headers.*}}`.
class Jabvox::Flows::Nodes::Triggers::WebhookNode
  TYPE = 'trigger.webhook'
  LABEL = 'Webhook entrante'
  DEFAULT_METHODS = %w[POST].freeze

  def self.register_on(registry)
    registry.register(TYPE, label: LABEL)
  end

  # Métodos aceptados. Sin configurar, solo POST.
  def self.allowed_methods(node)
    raw = params_of(node)['allowedMethods']
    list = Jabvox::Flows::Nodes::Params.str_list(raw).map(&:upcase)
    list.presence || DEFAULT_METHODS
  end

  def self.method_allowed?(node, http_method)
    allowed_methods(node).include?(http_method.to_s.upcase)
  end

  # Secreto adicional OPCIONAL. Se compara de forma timing-safe: sin esto una
  # comparación normal filtra el secreto por el tiempo de respuesta.
  def self.secret_valid?(node, provided)
    expected = params_of(node)['secret'].to_s
    return true if expected.blank?

    ActiveSupport::SecurityUtils.secure_compare(expected, provided.to_s)
  end

  def self.matches?(node, payload = {})
    payload = (payload || {}).stringify_keys
    method_allowed?(node, payload['method'] || 'POST') &&
      secret_valid?(node, payload['secret'])
  end

  def self.params_of(node)
    node.respond_to?(:params) && node.params.is_a?(Hash) ? node.params : {}
  end
end
