# frozen_string_literal: true

# Error de una pasarela de pago. Archivo propio para que Zeitwerk lo resuelva
# independientemente del orden de carga de los adaptadores.
class Jabvox::Billing::Gateways::GatewayError < StandardError; end
