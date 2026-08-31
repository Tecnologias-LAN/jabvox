# frozen_string_literal: true

# integration.webhook_out — POST saliente a una URL externa (notificación).
class Jabvox::Flows::Nodes::Integration::WebhookOutNode < Jabvox::Flows::Nodes::Integration::Base
  type 'integration.webhook_out'
  label 'Webhook saliente'

  def perform
    result = http_call(method: 'POST', url: param(:url), headers: param(:headers),
                       body: hash_param(param(:payload)))
    output = { 'status' => result['status'], 'data' => result['data'] }

    with_status(output, result['status'])
  end
end
