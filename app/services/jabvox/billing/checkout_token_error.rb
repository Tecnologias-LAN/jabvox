# frozen_string_literal: true

# Error del token de checkout (firma inválida/expirada). Archivo propio para Zeitwerk.
class Jabvox::Billing::CheckoutTokenError < StandardError; end
