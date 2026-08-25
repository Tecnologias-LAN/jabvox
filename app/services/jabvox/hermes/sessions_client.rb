# frozen_string_literal: true

# Cliente NATIVO de la Sessions REST API de Hermes (NousResearch), no de OpenAI.
#
# Contrato oficial (docs Hermes, gated por API_SERVER_KEY):
#   POST /api/sessions                 → crea una sesión, devuelve { id / session_id }
#   POST /api/sessions/{id}/chat       → un turno síncrono, body { "input": "<texto>" }
#   GET  /v1/health                    → salud
# Auth: header  Authorization: Bearer <API_SERVER_KEY>
#
# Como en Telegram, el TEXTO del usuario se reenvía TAL CUAL (incluidos comandos como
# /model, /new, /status): Hermes los interpreta. Jabvox no procesa comandos.
#
# base_url = host:puerto (ZeroTier), p.ej. http://10.147.100.1:9119 — los paths los arma
# este cliente con `sessions_path` (default /api/sessions). Soporta redes locales ZeroTier.
class Jabvox::Hermes::SessionsClient
  OPEN_TIMEOUT = 5
  TIMEOUT = 120 # un turno de agente puede tardar

  Result = Struct.new(:success, :text, :session_id, :error, :status, keyword_init: true) do
    def success? = success
  end

  HEALTH_PATHS = %w[v1/health health].freeze

  def initialize(base_url:, token:, sessions_path: '/api/sessions')
    @base_url = base_url.to_s.strip
    @token = token.to_s
    @sessions_path = sessions_path.presence || '/api/sessions'
  end

  # Salud del gateway de Hermes (prueba de conexión al ligar).
  def health
    HEALTH_PATHS.each do |path|
      resp = conn.get(path)
      return Result.new(success: true, status: resp.status) if resp.success?
    end
    Result.new(success: false, error: 'Hermes no respondió health')
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  # Crea una sesión nueva y devuelve su id.
  def create_session
    resp = conn.post(clean(@sessions_path)) { |r| r.body = {} }
    return Result.new(success: false, error: remote_error(resp), status: resp.status) unless resp.success?

    Result.new(success: true, session_id: extract_session_id(resp.body), status: resp.status)
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  # Envía un turno síncrono a una sesión existente. `input` es el texto del usuario tal cual.
  def chat(session_id, input)
    path = "#{clean(@sessions_path)}/#{session_id}/chat"
    resp = conn.post(path) { |r| r.body = { input: input.to_s } }
    return Result.new(success: false, error: remote_error(resp), status: resp.status) unless resp.success?

    Result.new(success: true, text: extract_text(resp.body), session_id: session_id, status: resp.status)
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  private

  def conn
    @conn ||= Faraday.new(url: normalize(@base_url)) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.options.open_timeout = OPEN_TIMEOUT
      f.options.timeout = TIMEOUT
      f.headers['Authorization'] = "Bearer #{@token}"
      f.adapter Faraday.default_adapter
    end
  end

  # base_url termina en '/'; los paths internos empiezan sin '/'.
  def normalize(url)
    url.end_with?('/') ? url : "#{url}/"
  end

  def clean(path)
    path.to_s.delete_prefix('/').delete_suffix('/')
  end

  # id de sesión tolerante a varias formas de la respuesta.
  def extract_session_id(body)
    return nil unless body.is_a?(Hash)

    body['id'] || body['session_id'] || body.dig('session', 'id') || body.dig('data', 'id')
  end

  # Texto final del asistente, tolerante al formato (output/message/content/response/text).
  # Hermes puede devolver output como array de items (estilo /v1/responses) o string.
  def extract_text(body)
    return body.to_s unless body.is_a?(Hash)

    raw = body['output'] || body['message'] || body['content'] || body['response'] || body['text']
    stringify(raw)
  end

  def stringify(raw)
    case raw
    when String then raw
    when Array then raw.map { |item| item_text(item) }.join("\n")
    when Hash then item_text(raw)
    else raw.to_s
    end
  end

  def item_text(item)
    return item.to_s unless item.is_a?(Hash)

    item['text'] || item['content'] || item.to_s
  end

  def remote_error(resp)
    body = resp.body
    msg = body.is_a?(Hash) ? (body['error'] || body['message'] || body['detail']) : nil
    "Hermes respondió #{resp.status}#{": #{msg}" if msg.present?}"
  end

  def net_error(error)
    case error
    when Faraday::TimeoutError then 'Hermes no respondió a tiempo (timeout).'
    when Faraday::ConnectionFailed then 'No se pudo conectar con Hermes (revisa la red ZeroTier).'
    else "Error al contactar Hermes: #{error.class}"
    end
  end
end
