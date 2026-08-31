# frozen_string_literal: true

# Base de los nodos `integration.*`: los únicos que salen a Internet. Centraliza
# el guard anti-SSRF, el timeout acotado y el parseo de la respuesta.
class Jabvox::Flows::Nodes::Integration::Base < Jabvox::Flows::Nodes::Base
  DEFAULT_TIMEOUT_MS = 15_000
  MIN_TIMEOUT_MS = 1_000
  MAX_TIMEOUT_MS = 120_000

  METHODS = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'PUT' => Net::HTTP::Put,
              'PATCH' => Net::HTTP::Patch, 'DELETE' => Net::HTTP::Delete }.freeze

  private

  # Respuesta cruda: { 'status', 'headers', 'data' }. NO sigue redirecciones.
  def http_call(method:, url:, headers: nil, body: nil, timeout_ms: nil)
    uri = Jabvox::Flows::Nodes::Integration::UrlGuard.assert_safe_url!(url)
    request = build_request(method, uri, headers, body)
    response = send_request(uri, request, timeout_ms)

    { 'status' => response.code.to_i, 'headers' => response_headers(response),
      'data' => parse_body(response) }
  end

  def build_request(method, uri, headers, body)
    klass = METHODS[first_filled(method, 'GET').upcase]
    fail_with!("El método HTTP \"#{method}\" no está soportado. Usa GET, POST, PUT, PATCH o DELETE.") if klass.nil?

    request = klass.new(uri)
    hash_param(headers).each { |key, value| request[key.to_s] = value.to_s }
    attach_body(request, body)
    request
  end

  # Cuerpo JSON salvo que las cabeceras ya fijen otro Content-Type.
  def attach_body(request, body)
    return if body.nil? || body == ''

    if body.is_a?(String)
      request.body = body
    else
      request['Content-Type'] ||= 'application/json'
      request.body = body.to_json
    end
  end

  def send_request(uri, request, timeout_ms)
    seconds = timeout_seconds(timeout_ms)
    # open Y read: con solo uno la petición se queda colgada en la otra fase.
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                                            open_timeout: seconds, read_timeout: seconds,
                                            write_timeout: seconds) do |http|
      http.request(request)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
    fail_with!("La petición a #{uri.host} superó el tiempo de espera (#{seconds} s).")
  rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
    fail_with!("No se pudo conectar con #{uri.host}: #{e.message}")
  end

  # '' cae a 15 s; un 0 explícito NO significa "sin timeout": se acota al mínimo.
  def timeout_seconds(raw)
    int_or(raw, DEFAULT_TIMEOUT_MS, min: MIN_TIMEOUT_MS, max: MAX_TIMEOUT_MS) / 1000.0
  end

  def response_headers(response)
    response.each_header.to_h.transform_keys(&:to_s)
  end

  # JSON solo si el Content-Type lo declara; si no, el texto crudo.
  def parse_body(response)
    text = response.body.to_s
    return nil if text.empty?
    return text unless response['Content-Type'].to_s.include?('json')

    JSON.parse(text)
  rescue JSON::ParserError
    text
  end

  def hash_param(value)
    value.is_a?(Hash) ? value : {}
  end

  # Fallo por status: `ok` en false con el mensaje que espera el catálogo.
  def with_status(output, status)
    return ok(output) if status < 400

    Jabvox::Flows::Engine::NodeResult.new(ok: false, output: output, error: "HTTP #{status}")
  end
end
