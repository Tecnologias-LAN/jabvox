# frozen_string_literal: true

# Cliente del API de RUNS de Hermes — el modo "con estado" del agente.
#
# A diferencia de /v1/chat/completions (un turno suelto, sin control), un run puede PARARSE
# a pedir aprobación humana antes de ejecutar algo que su escaneo de seguridad marcó como
# riesgoso. Sin este cliente esa pregunta nunca llegaba al operador y el agente se quedaba
# bloqueado sin explicación.
#
# Contrato verificado EN VIVO contra el gateway (no según documentación, que tenía tres
# errores: el body es `input` y no `messages`; steer usa `input`/`message`/`text` y no
# `guidance`; y el prefijo /p/<perfil>/ solo aplica si el gateway multiplexa perfiles):
#
#   POST /v1/runs                     {input:} → 202 {run_id, status, replayed}
#   GET  /v1/runs/{id}                → {status, session_id, output, usage, runtime, approval?}
#   GET  /v1/runs/{id}/events         → SSE de eventos del run
#   POST /v1/runs/{id}/approval       {choice:, request_id:} → {resolved:}
#   POST /v1/runs/{id}/steer          {input:} → {accepted:}
#   POST /v1/runs/{id}/stop           → {status: "stopping"}
#
# Cuando un run queda en `waiting_for_approval`, el estado trae `approval` con el comando ya
# REDACTADO por Hermes (nunca credenciales), la descripción del hallazgo y `choices` con las
# opciones válidas. `choices` es DINÁMICO (p.ej. sin "always" si allow_permanent es false),
# así que la UI debe renderizar los botones desde ese array y nunca hardcodearlos.
class Jabvox::Hermes::RunsClient
  OPEN_TIMEOUT = 5
  TIMEOUT = 120
  # El stream de un run vive lo que dure el turno, que con una aprobación de por medio
  # incluye el tiempo que tarde el humano en decidir (Hermes corta a los 5 min por defecto).
  STREAM_TIMEOUT = 600

  Result = Struct.new(:success, :data, :error, :status, keyword_init: true) do
    def success? = success
  end

  def initialize(base_url:, token:)
    @base_url = base_url.to_s.strip
    @token = token.to_s
  end

  # Inicia un run. Devuelve {run_id, status} inmediatamente (202): el agente sigue trabajando
  # en segundo plano y su progreso se sigue por el stream de eventos.
  #
  # `input` es el texto del usuario. `history` se manda aparte como conversation_history para
  # que el agente tenga el contexto previo de la conversación.
  def create(input, session_id: nil, history: [], llm_overrides: nil)
    body = { input: input.to_s }
    body[:session_id] = session_id if session_id.present?
    body[:conversation_history] = history if history.present?
    if llm_overrides.present?
      overrides = llm_overrides.transform_keys(&:to_sym)
      body[:model] = overrides[:model] if overrides[:model].present?
      body[:provider] = overrides[:provider] if overrides[:provider].present?
    end
    post('v1/runs', body)
  end

  # Estado actual del run (para poll y para leer la aprobación pendiente).
  def status(run_id)
    get("v1/runs/#{run_id}")
  end

  # Responde una aprobación pendiente. `choice` debe ser una de las que vino en
  # approval.choices; `request_id` identifica la solicitud exacta que se responde.
  def approve(run_id, choice:, request_id: nil)
    body = { choice: choice.to_s }
    body[:request_id] = request_id if request_id.present?
    post("v1/runs/#{run_id}/approval", body)
  end

  # Inyecta guía a un run EN CURSO. El campo es `input` (verificado: `guidance` da 400).
  def steer(run_id, text)
    post("v1/runs/#{run_id}/steer", { input: text.to_s })
  end

  def stop(run_id)
    post("v1/runs/#{run_id}/stop", {})
  end

  # Fija el modelo/proveedor de una sesión (el equivalente a /model). Vive bajo /api/, no /v1/.
  def set_session_model(session_id, model:, provider: nil)
    body = { model: model.to_s }
    body[:provider] = provider if provider.present?
    post_absolute(admin_url("sessions/#{session_id}/model"), body)
  end

  # Stream SSE de eventos del run. Llama a `on_chunk` con cada frame crudo, tal cual llega,
  # para poder retransmitirlo al navegador sin reinterpretarlo.
  def events(run_id, on_chunk:)
    stream_conn.get(api_path("v1/runs/#{run_id}/events")) do |req|
      req.headers['Accept'] = 'text/event-stream'
      req.options.on_data = proc { |chunk, _bytes, _env| on_chunk.call(chunk) }
    end
    true
  rescue Faraday::Error => e
    on_chunk.call("data: #{{ error: net_error(e) }.to_json}\n\n")
    false
  end

  private

  # El gateway puede servir un solo perfil (rutas en la raíz) o multiplexar varios bajo
  # /p/<perfil>/. La base_url configurada ya incluye el prefijo cuando toca, así que aquí
  # solo se evita duplicar el /v1 final.
  def api_path(suffix)
    base = @base_url.to_s.chomp('/')
    return suffix.delete_prefix('v1/') if base.end_with?('/v1')

    suffix
  end

  # Las rutas de administración cuelgan de /api/, no de /v1/.
  def admin_url(suffix)
    base = @base_url.to_s.chomp('/')
    root = base.end_with?('/v1') ? base[0...-2] : "#{base}/"
    "#{root}api/#{suffix}"
  end

  def get(suffix)
    build_result(conn.get(api_path(suffix)))
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  def post(suffix, body)
    build_result(conn.post(api_path(suffix), body))
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  def post_absolute(url, body)
    build_result(
      Faraday.post(url, body.to_json, auth_header.merge('Content-Type' => 'application/json'))
    )
  rescue Faraday::Error => e
    Result.new(success: false, error: net_error(e))
  end

  def auth_header
    { 'Authorization' => "Bearer #{@token}" }
  end

  def build_result(resp)
    body = parse_body(resp.body)
    return Result.new(success: true, data: body, status: resp.status) if resp.success?

    Result.new(success: false, error: error_message(body, resp.status), status: resp.status)
  end

  def parse_body(body)
    return body unless body.is_a?(String)

    JSON.parse(body)
  rescue JSON::ParserError
    body
  end

  def error_message(body, status)
    return "Hermes respondió #{status}" unless body.is_a?(Hash)

    err = body['error']
    msg = err.is_a?(Hash) ? err['message'] : err
    msg.presence || "Hermes respondió #{status}"
  end

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

  def stream_conn
    @stream_conn ||= Faraday.new(url: normalize(@base_url)) do |f|
      f.options.open_timeout = OPEN_TIMEOUT
      f.options.timeout = STREAM_TIMEOUT
      f.headers['Authorization'] = "Bearer #{@token}"
      f.adapter Faraday.default_adapter
    end
  end

  def normalize(url)
    u = url.to_s.strip.chomp('/')
    u.start_with?('http://', 'https://') ? "#{u}/" : "http://#{u}/"
  end

  def net_error(error)
    case error
    when Faraday::ConnectionFailed then 'No se pudo conectar con Hermes'
    when Faraday::TimeoutError then 'Hermes no respondió a tiempo'
    else "Error de red con Hermes: #{error.class}"
    end
  end
end
