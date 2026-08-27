# frozen_string_literal: true

# Cliente del API Server OpenAI-compatible de Hermes (NousResearch).
#
# Tu Hermes expone (confirmado por el propio Hermes): API Server compatible con OpenAI en
# <base>/v1/chat/completions, autenticado con Bearer API_SERVER_KEY, modelo p.ej. "agente-miguel".
# GET <base>/v1/models y GET <base>/v1/health para descubrir/verificar.
#
# Como en Telegram, el TEXTO del usuario se reenvía TAL CUAL (incluidos /model, /new...):
# Hermes los interpreta. Multi-turno: se reenvía el historial de mensajes (stateless).
#
# base_url = host:puerto ZeroTier, p.ej. http://10.147.100.1:9119 — el cliente añade /v1.
#
# Mantiene la interfaz (health/chat) que usan el relay y AiChatService. `create_session`
# queda como no-op compatible (el API OpenAI es stateless; el contexto va en `messages`).
#
# Cliente único hacia un agente de Hermes: chat (sync/stream), modelos y cron. Es largo a
# propósito porque agrupa toda la API de un agente en un solo lugar coherente.
# rubocop:disable Metrics/ClassLength
class Jabvox::Hermes::SessionsClient
  OPEN_TIMEOUT = 5
  TIMEOUT = 120 # un turno de agente puede tardar

  Result = Struct.new(:success, :text, :session_id, :error, :status, keyword_init: true) do
    def success? = success
  end

  HEALTH_PATHS = %w[v1/health health].freeze

  def initialize(base_url:, token:, model: nil, **_ignored)
    @base_url = base_url.to_s.strip
    @token = token.to_s
    @model = model.presence || ENV['HERMES_MODEL'].presence || 'hermes'
  end

  # Salud del gateway de Hermes (prueba de conexión al ligar).
  def health
    HEALTH_PATHS.each do |path|
      resp = raw_conn.get(path)
      return Result.new(success: true, status: resp.status) if resp.success?
    end
    Result.new(success: false, error: 'Hermes no respondió health')
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  # API OpenAI stateless: no hay sesión que crear. Se mantiene por compatibilidad de interfaz.
  def create_session
    Result.new(success: true, session_id: nil)
  end

  # Un turno. `input` puede ser un string (texto del usuario) o un array de mensajes estilo
  # OpenAI [{role:, content:}] para multi-turno. Reenvía tal cual; Hermes interpreta comandos.
  def chat(_session_id, input)
    messages = input.is_a?(Array) ? input : [{ role: 'user', content: input.to_s }]
    resp = raw_conn.post(api_path('chat/completions')) do |r|
      r.body = { model: @model, messages: messages }
    end
    return Result.new(success: false, error: remote_error(resp), status: resp.status) unless resp.success?

    Result.new(success: true, text: extract_text(resp.body), status: resp.status)
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  # Turno en STREAMING (SSE). Reenvía tal cual cada línea del stream de Hermes al bloque
  # `on_chunk` (texto fluyendo + eventos hermes.tool.progress + [DONE]), igual que Telegram.
  # Devuelve el texto completo acumulado. `on_session` recibe el X-Hermes-Session-Id si llega.
  def chat_stream(input, on_chunk:, on_session: nil)
    messages = input.is_a?(Array) ? input : [{ role: 'user', content: input.to_s }]
    full = +''
    stream_conn.post(api_path('chat/completions')) do |req|
      req.headers['Accept'] = 'text/event-stream'
      req.body = { model: @model, messages: messages, stream: true }
      req.options.on_data = proc do |chunk, _bytes, env|
        on_session&.call(env.response_headers['x-hermes-session-id']) if on_session && env
        full << extract_stream_text(chunk)
        on_chunk.call(chunk)
      end
    end
    full
  rescue Faraday::Error => e
    on_chunk.call("data: #{{ error: net_error(e) }.to_json}\n\n")
    full
  end

  # Lista de modelos que expone el Hermes (GET .../v1/models) — para el sync de modelos.
  def models
    resp = raw_conn.get(api_path('models'))
    return Result.new(success: false, error: remote_error(resp), status: resp.status) unless resp.success?

    list = resp.body.is_a?(Hash) ? (resp.body['data'] || []) : Array(resp.body)
    Result.new(success: true, text: nil, status: resp.status).tap { |r| r.define_singleton_method(:data) { list } }
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  # Opciones de modelos POR AGENTE (GET .../<agente>/api/model/options). Devuelve la lista
  # cruda de proveedores/modelos que Hermes reporta para ese agente.
  def model_options
    api_get('model/options')
  end

  # --- Cron / tareas programadas POR AGENTE (.../<agente>/api/jobs) ---

  def list_jobs
    api_get('jobs?include_disabled=true')
  end

  def create_job(attrs)
    api_post('jobs', attrs)
  end

  def pause_job(id)
    api_post("jobs/#{id}/pause", {})
  end

  def resume_job(id)
    api_post("jobs/#{id}/resume", {})
  end

  def run_job(id)
    api_post("jobs/#{id}/run", {})
  end

  def delete_job(id)
    build_data_result(Faraday.delete(admin_url("jobs/#{id}"), nil, auth_header))
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  private

  # Path del endpoint OpenAI respetando el base_url. Si la base ya termina en /v1 (p.ej.
  # http://host:8642/p/agente-miguel/v1) NO se duplica el /v1; si no, se antepone.
  def api_path(suffix)
    base = @base_url.to_s.chomp('/')
    base.end_with?('/v1') ? suffix : "v1/#{suffix}"
  end

  # URL ABSOLUTA del API de administración del agente (.../<agente>/api/...). La base termina
  # en /v1; se reemplaza ese /v1 final por /api para llegar a model/options y jobs.
  def admin_url(suffix)
    base = @base_url.to_s.chomp('/')
    root = base.end_with?('/v1') ? base[0...-2] : "#{base}/" # quita "v1", deja la barra
    "#{root}api/#{suffix}"
  end

  def api_get(suffix)
    build_data_result(Faraday.get(admin_url(suffix), nil, auth_header))
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  def api_post(suffix, body)
    build_data_result(
      Faraday.post(admin_url(suffix), body.to_json, auth_header.merge('Content-Type' => 'application/json'))
    )
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  def auth_header
    { 'Authorization' => "Bearer #{@token}" }
  end

  def build_data_result(resp)
    body = parse_body(resp.body)
    if resp.success?
      Result.new(success: true, status: resp.status).tap do |r|
        r.define_singleton_method(:data) { body }
      end
    else
      Result.new(success: false, error: "Hermes respondió #{resp.status}", status: resp.status)
    end
  end

  def parse_body(body)
    return body unless body.is_a?(String)

    JSON.parse(body)
  rescue JSON::ParserError
    body
  end

  def raw_conn
    @raw_conn ||= Faraday.new(url: normalize(@base_url)) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.options.open_timeout = OPEN_TIMEOUT
      f.options.timeout = TIMEOUT
      f.headers['Authorization'] = "Bearer #{@token}"
      f.adapter Faraday.default_adapter
    end
  end

  # Conexión para streaming: request JSON pero SIN parsear la respuesta (llega por on_data).
  def stream_conn
    @stream_conn ||= Faraday.new(url: normalize(@base_url)) do |f|
      f.request :json
      f.options.open_timeout = OPEN_TIMEOUT
      f.options.timeout = TIMEOUT
      f.headers['Authorization'] = "Bearer #{@token}"
      f.adapter Faraday.default_adapter
    end
  end

  # Extrae el texto (delta.content) de los chunks SSE para acumular la respuesta final.
  def extract_stream_text(chunk)
    out = +''
    chunk.to_s.each_line do |line|
      next unless line.start_with?('data:')

      data = line.sub('data:', '').strip
      next if data.empty? || data == '[DONE]'

      begin
        json = JSON.parse(data)
        out << json.dig('choices', 0, 'delta', 'content').to_s
      rescue JSON::ParserError
        next
      end
    end
    out
  end

  def normalize(url)
    url.end_with?('/') ? url : "#{url}/"
  end

  # Texto final del asistente en formato OpenAI chat/completions.
  def extract_text(body)
    return body.to_s unless body.is_a?(Hash)

    body.dig('choices', 0, 'message', 'content').to_s.presence ||
      body.dig('choices', 0, 'text').to_s
  end

  def remote_error(resp)
    msg = error_message(resp.body)
    "Hermes respondió #{resp.status}#{": #{msg}" if msg.present?}"
  end

  def error_message(body)
    return nil unless body.is_a?(Hash)

    err = body['error']
    err.is_a?(Hash) ? err['message'] : err
  end

  def net_error(error)
    case error
    when Faraday::TimeoutError then 'Hermes no respondió a tiempo (timeout).'
    when Faraday::ConnectionFailed then 'No se pudo conectar con Hermes (revisa la red ZeroTier).'
    else "Error al contactar Hermes: #{error.class}"
    end
  end
end
# rubocop:enable Metrics/ClassLength
