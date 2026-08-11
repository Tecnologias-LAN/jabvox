# frozen_string_literal: true

require 'net/http'

# Adaptador de la pasarela Bold (Colombia). Implementación de punta a punta según la
# documentación oficial: https://developers.bold.co
#
# Sandbox y producción comparten la MISMA URL base (integrations.api.bold.co); lo que
# cambia es la LLAVE (de pruebas vs producción) y, en sandbox, el secreto del webhook es
# cadena vacía. Ver https://developers.bold.co/api-integrations/integration-sandbox
#
# Secretos (en .env, NUNCA en BD):
#   BOLD_API_KEY        - llave de identidad para llamar a la API (header x-api-key)
#   BOLD_SECRET_KEY     - llave secreta que firma los webhooks (vacía en sandbox)
#
# Datos públicos (en JabvoxPaymentGatewayConfig, editable desde Super Admin):
#   public_token        - llave de identidad pública para el botón de checkout en la web
#   checkout_base_url   - base del checkout de Bold
#
# Modo sandbox: se activa con BOLD_ENV=sandbox (o config.settings['env']=='sandbox').
class Jabvox::Billing::Gateways::Bold < Jabvox::Billing::Gateways::Base
  API_BASE = ENV.fetch('BOLD_API_BASE', 'https://integrations.api.bold.co')
  APPROVED_TYPES = %w[SALE_APPROVED].freeze
  REJECTED_TYPES = %w[SALE_REJECTED VOID_APPROVED VOID_REJECTED].freeze

  # POST /online/link/v1 → { checkout_url:, reference: }.
  # Bold devuelve { payload: { payment_link:, url: }, errors: [] }.
  def create_checkout(amount_cents:, currency:, reference:, metadata:)
    body = {
      amount_type: 'CLOSE',
      amount: { currency: currency, total_amount: to_bold_amount(amount_cents, currency) },
      reference: reference,
      description: checkout_description(metadata),
      callback_url: metadata[:callback_url],
      payer_email: metadata[:payer_email]
    }.compact

    data = post_json("#{API_BASE}/online/link/v1", body)
    payload = data['payload'] || {}
    raise Jabvox::Billing::Gateways::GatewayError, "Bold no devolvió url de checkout: #{data['errors']}" if payload['url'].blank?

    { checkout_url: payload['url'], reference: reference, gateway_link_id: payload['payment_link'] }
  end

  # Verifica la firma del webhook de Bold (doc oficial):
  #   1) codificar el cuerpo crudo en Base64
  #   2) HMAC-SHA256 de ese Base64 con la LLAVE SECRETA
  #   3) salida en HEXADECIMAL
  # Se compara en tiempo constante con el header x-bold-signature.
  # En sandbox la llave secreta es cadena vacía.
  def verify_webhook_signature(request, raw_body)
    received = request.headers['x-bold-signature'].to_s
    return false if received.blank?

    encoded_body = Base64.strict_encode64(raw_body.to_s)
    expected = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, encoded_body)
    secure_compare(expected, received)
  end

  # Consulta el ESTADO REAL del pago a la API de Bold (doble validación, además de la
  # firma): GET /v1/payment/{reference}. Nunca confía solo en el payload del webhook.
  def fetch_payment_status(reference)
    data = get_json("#{API_BASE}/v1/payment/#{reference}")
    payload = data['payload'] || data
    status = payload['status'].to_s.upcase
    {
      approved: %w[APPROVED SALE_APPROVED].include?(status),
      status: status,
      reference: reference,
      amount_cents: extract_amount_cents(payload)
    }
  rescue Jabvox::Billing::Gateways::GatewayError => e
    # Si la consulta no está disponible, devolvemos indeterminado; la decisión final la
    # toma quien llama combinándolo con la firma verificada del webhook.
    Rails.logger.warn("[Bold] no se pudo consultar estado de #{reference}: #{e.message}")
    { approved: false, status: 'UNKNOWN', reference: reference, amount_cents: nil }
  end

  # Interpreta el TIPO del evento del webhook ya verificado por firma.
  #   { approved:, status:, reference:, amount_cents: }
  def parse_webhook_event(payload)
    data = payload['data'] || {}
    type = payload['type'].to_s.upcase
    {
      approved: APPROVED_TYPES.include?(type),
      rejected: REJECTED_TYPES.include?(type),
      status: type,
      reference: data.dig('metadata', 'reference') || data['reference'],
      payment_id: data['payment_id'],
      amount_cents: extract_amount_cents(data)
    }
  end

  private

  def sandbox?
    ENV.fetch('BOLD_ENV', config.settings&.dig('env')).to_s == 'sandbox'
  end

  # La llave que firma el webhook. En sandbox es cadena vacía (doc oficial).
  def webhook_secret
    return '' if sandbox?

    ENV.fetch('BOLD_SECRET_KEY', '')
  end

  def checkout_description(metadata)
    "Plan Jabvox #{metadata[:plan_id]}".slice(0, 100)
  end

  # Bold recibe montos en la unidad principal (COP sin decimales; USD con 2). Guardamos
  # todo en centavos internamente.
  def to_bold_amount(amount_cents, currency)
    currency.to_s.upcase == 'USD' ? (amount_cents / 100.0) : (amount_cents / 100)
  end

  def auth_header
    "x-api-key #{env_secret('API_KEY')}"
  end

  def extract_amount_cents(data)
    total = data.dig('amount', 'total') || data['total_amount'] || data.dig('amount', 'total_amount')
    return nil if total.nil?

    currency = (data.dig('amount', 'currency') || data['currency']).to_s.upcase
    currency == 'USD' ? (total.to_f * 100).round : (total.to_i * 100)
  end

  def post_json(url, body)
    req = Net::HTTP::Post.new(URI(url))
    req['Authorization'] = auth_header
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
    run(req, url)
  end

  def get_json(url)
    req = Net::HTTP::Get.new(URI(url))
    req['Authorization'] = auth_header
    run(req, url)
  end

  def run(req, url)
    uri = URI(url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                              open_timeout: 10, read_timeout: 20) do |http|
      http.request(req)
    end
    raise Jabvox::Billing::Gateways::GatewayError, "Bold respondió #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body.presence || '{}')
  rescue JSON::ParserError => e
    raise Jabvox::Billing::Gateways::GatewayError, "Respuesta de Bold no es JSON: #{e.message}"
  end

  # Comparación en tiempo constante (evita timing attacks).
  def secure_compare(expected, received)
    ActiveSupport::SecurityUtils.secure_compare(expected, received)
  rescue ArgumentError
    false # longitudes distintas
  end
end
