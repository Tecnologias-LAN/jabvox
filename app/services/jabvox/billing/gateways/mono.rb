# frozen_string_literal: true

# Adaptador de Mono. ESQUELETO con la interfaz completa: la selección de proveedor y el
# token público ya funcionan desde el panel; falta completar las llamadas HTTP concretas
# y la verificación de firma cuando se active Mono.
#
# Firma de webhook: HMAC del cuerpo crudo con MONO_EVENTS_SECRET (header de firma de Mono),
# comparada en tiempo constante. Estado real: consulta del pago vía API de Mono.
#
# rubocop:disable Lint/UnusedMethodArgument
class Jabvox::Billing::Gateways::Mono < Jabvox::Billing::Gateways::Base
  def create_checkout(amount_cents:, currency:, reference:, metadata:)
    # TODO(mono): crear el checkout vía API de Mono con la metadata.
    raise Jabvox::Billing::Gateways::GatewayError, 'Adaptador Mono pendiente de completar (create_checkout)'
  end

  def verify_webhook_signature(_request, _raw_body)
    # TODO(mono): recomputar el HMAC del cuerpo y compararlo en tiempo constante.
    raise Jabvox::Billing::Gateways::GatewayError, 'Adaptador Mono pendiente de completar (verify_webhook_signature)'
  end

  def fetch_payment_status(_reference)
    # TODO(mono): consultar el pago y normalizar { approved:, status:, ... }.
    raise Jabvox::Billing::Gateways::GatewayError, 'Adaptador Mono pendiente de completar (fetch_payment_status)'
  end

  def parse_webhook_event(_payload)
    # TODO(mono): normalizar el evento a { approved:, rejected:, status:, reference:, ... }.
    raise Jabvox::Billing::Gateways::GatewayError, 'Adaptador Mono pendiente de completar (parse_webhook_event)'
  end
end
# rubocop:enable Lint/UnusedMethodArgument
