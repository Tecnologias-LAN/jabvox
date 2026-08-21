# frozen_string_literal: true

require 'net/http'

# Adaptador de la pasarela Bold (Colombia). Implementación de punta a punta según la
# documentación oficial: https://developers.bold.co
#
# Sandbox y producción comparten la MISMA URL base (integrations.api.bold.co); lo que
# cambia es la LLAVE (de pruebas vs producción) y, en sandbox, el secreto del webhook es
# cadena vacía. Ver https://developers.bold.co/api-integrations/integration-sandbox
#
# TODO se administra desde el Super Admin (JabvoxPaymentGatewayConfig); ya NO hay
# secretos en variables de entorno. Los secretos van CIFRADOS en reposo:
#   api_key      - llave privada de identidad para la API (header x-api-key). Cifrada.
#   secret_key   - llave que firma los webhooks (vacía/ignorada en sandbox). Cifrada.
#   public_token - llave PÚBLICA para el botón de checkout en la web.
#   checkout_base_url - base del checkout de Bold.
#   sandbox      - modo pruebas (booleano). En sandbox el secreto de firma es cadena vacía.
#
# Única variable de entorno restante (no secreta): BOLD_API_BASE, la URL base de la API.
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

  # Modo sandbox: se administra desde el Super Admin (columna `sandbox`).
  def sandbox?
    config.sandbox?
  end

  # La llave que firma el webhook. En sandbox es cadena vacía (doc oficial). En
  # producción DEBE existir: si faltara, un secreto vacío haría la firma trivialmente
  # falsificable (cualquiera podría firmar un pago). Por eso levantamos en vez de caer
  # a '' silenciosamente. Se administra desde el Super Admin (cifrada en reposo).
  def webhook_secret
    return '' if sandbox?

    secret = config.secret_key.to_s
    if secret.blank?
      raise Jabvox::Billing::Gateways::GatewayError,
            'La secret_key de Bold no está configurada en el Super Admin: no se puede verificar la firma del webhook'
    end
    secret
  end

  def checkout_description(metadata)
    "Plan Jabvox #{metadata[:plan_id]}".slice(0, 100)
  end

  # Bold recibe montos en la unidad principal (COP sin decimales; USD con 2). Guardamos
  # todo en centavos internamente.
  def to_bold_amount(amount_cents, currency)
    currency.to_s.upcase == 'USD' ? (amount_cents / 100.0) : (amount_cents / 100)
  end

  # La API de Payment Links de Bold se autentica con la LLAVE SECRETA en el header
  # `Authorization: x-api-key {secret_key}` (NO con la llave de identidad, que es solo
  # para el botón/checkout embebido en el frontend). Usar la de identidad da 403.
  def auth_header
    key = config.secret_key.to_s
    if key.blank?
      raise Jabvox::Billing::Gateways::GatewayError,
            'La llave secreta (secret_key) de Bold no está configurada en el Super Admin'
    end
    "x-api-key #{key}"
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
