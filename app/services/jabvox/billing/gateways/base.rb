# frozen_string_literal: true

# Interfaz común de las pasarelas de pago (Bold/Wompi/Mono). Cada adaptador concreto
# implementa estos métodos. La selección del proveedor activo y su token PÚBLICO vienen
# de JabvoxPaymentGatewayConfig (editable desde Super Admin, sin redeploy); los SECRETOS
# (llave privada, secreto de firma) se leen de variables de entorno dentro del adaptador.
class Jabvox::Billing::Gateways::Base
  attr_reader :config

  def initialize(config)
    @config = config
  end

  # Devuelve el adaptador de la pasarela activa, o nil si no hay ninguna configurada.
  def self.for_active
    cfg = JabvoxPaymentGatewayConfig.active_gateway
    return nil if cfg.nil?

    build(cfg)
  end

  # Construye el adaptador concreto según config.provider.
  def self.build(config)
    case config.provider
    when 'bold' then Jabvox::Billing::Gateways::Bold.new(config)
    when 'wompi' then Jabvox::Billing::Gateways::Wompi.new(config)
    when 'mono' then Jabvox::Billing::Gateways::Mono.new(config)
    else raise Jabvox::Billing::Gateways::GatewayError, "Pasarela desconocida: #{config.provider}"
    end
  end

  def provider
    config.provider
  end

  # Crea el checkout en la pasarela y devuelve { checkout_url:, reference: }.
  # metadata debe incluir account_id, plan_id, idempotency_key.
  def create_checkout(_amount_cents:, _currency:, _reference:, _metadata:)
    raise NotImplementedError
  end

  # Verifica la firma del webhook. `request` es el ActionDispatch::Request.
  # Devuelve true/false. NUNCA debe confiar en el payload sin esto.
  def verify_webhook_signature(_request, _raw_body)
    raise NotImplementedError
  end

  # Consulta el ESTADO REAL del pago a la pasarela (no confía en el payload del
  # webhook). Devuelve un hash normalizado:
  #   { approved: bool, status: 'APPROVED'|'REJECTED'|..., reference:, amount_cents: }
  def fetch_payment_status(_reference)
    raise NotImplementedError
  end

  # Interpreta el payload YA VERIFICADO por firma y lo normaliza:
  #   { approved:, rejected:, status:, reference:, payment_id:, amount_cents: }
  def parse_webhook_event(_payload)
    raise NotImplementedError
  end

  private

  # Lee un secreto de ENV con nombre convencional por proveedor, p.ej.
  # BOLD_API_SECRET, WOMPI_EVENTS_SECRET. Levanta si falta (no se puede operar).
  def env_secret(suffix)
    key = "#{provider.upcase}_#{suffix}"
    ENV.fetch(key) { raise Jabvox::Billing::Gateways::GatewayError, "Falta la variable de entorno #{key}" }
  end
end
