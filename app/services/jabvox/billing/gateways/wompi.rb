# frozen_string_literal: true

# Adaptador de Wompi (Colombia). ESQUELETO con la interfaz completa: la selección de
# proveedor y el token público ya funcionan desde el panel; falta completar las llamadas
# HTTP concretas y la fórmula exacta de firma cuando se active Wompi.
#
# Firma de webhook de Wompi: SHA256 de la concatenación de los valores de las propiedades
# indicadas en `signature.properties` del evento + timestamp + WOMPI_EVENTS_SECRET,
# comparada con event['signature']['checksum'].
# Estado real: GET https://production.wompi.co/v1/transactions/:id
#
# rubocop:disable Lint/UnusedMethodArgument
class Jabvox::Billing::Gateways::Wompi < Jabvox::Billing::Gateways::Base
  def create_checkout(amount_cents:, currency:, reference:, metadata:)
    # TODO(wompi): crear el checkout/link de pago vía API de Wompi con la metadata.
    raise Jabvox::Billing::Gateways::GatewayError, 'Adaptador Wompi pendiente de completar (create_checkout)'
  end

  def verify_webhook_signature(_request, _raw_body)
    # TODO(wompi): recomputar el checksum SHA256 y compararlo en tiempo constante.
    raise Jabvox::Billing::Gateways::GatewayError, 'Adaptador Wompi pendiente de completar (verify_webhook_signature)'
  end

  def fetch_payment_status(_reference)
    # TODO(wompi): GET /v1/transactions/:id y normalizar { approved:, status:, ... }.
    raise Jabvox::Billing::Gateways::GatewayError, 'Adaptador Wompi pendiente de completar (fetch_payment_status)'
  end

  def parse_webhook_event(_payload)
    # TODO(wompi): normalizar el evento a { approved:, rejected:, status:, reference:, ... }.
    raise Jabvox::Billing::Gateways::GatewayError, 'Adaptador Wompi pendiente de completar (parse_webhook_event)'
  end
end
# rubocop:enable Lint/UnusedMethodArgument
