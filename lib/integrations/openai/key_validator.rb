module Integrations::Openai::KeyValidator
  TIMEOUT_SECONDS = 5

  # Resultado detallado de la validación: si es válida, el código HTTP y un mensaje del
  # proveedor (para mostrarle al usuario el motivo exacto, no un "inválida" a secas).
  Result = Struct.new(:valid, :code, :message, keyword_init: true) do
    def valid? = valid
  end

  # Booleano de compatibilidad (spec/modelo antiguos). Prefiere `validate` para el detalle.
  def self.valid?(api_key, base_url = nil)
    validate(api_key, base_url).valid?
  end

  # Valida la API key contra el proveedor y devuelve un Result con código y mensaje.
  # Con OpenAI oficial basta consultar /v1/models. Pero MUCHOS proveedores OpenAI-compatibles
  # (gateways, modelos propios como "Jabvox IA") NO exponen /v1/models o devuelven 401 en esa
  # ruta aunque la key SÍ sea válida para /v1/chat/completions (lo que la integración usa).
  # Por eso, con base_url propio confirmamos con chat/completions antes de rechazar.
  def self.validate(api_key, base_url = nil)
    return Result.new(valid: false, code: 'blank_api_key', message: 'La API key está vacía.') if api_key.blank?

    models = probe_models(api_key, base_url)
    # /models respondió algo != 401 (200, 404, 500…): key aceptada / no concluyente → válida.
    return Result.new(valid: true, code: models[:status], message: 'Conectado.') if models[:status] && models[:status] != 401

    if base_url.blank?
      # OpenAI OFICIAL: 401 = key inválida; sin respuesta (timeout) = transitorio → válida.
      return Result.new(valid: false, code: 401, message: openai_error_message(models)) if models[:status] == 401

      return Result.new(valid: true, code: nil, message: 'No se pudo verificar (red); se acepta provisionalmente.')
    end

    # Proveedor PROPIO: /models dio 401 o no respondió → confirmamos con chat/completions.
    chat_completions_result(api_key, base_url)

  rescue Faraday::Error => e
    # Error de red/timeout inesperado: no bloqueamos la activación por conectividad.
    Rails.logger.warn("[openai-key-validator] #{e.class}: #{e.message}")
    Result.new(valid: true, code: nil, message: "No se pudo verificar (#{e.class}); se acepta provisionalmente.")
  end

  # GET /v1/models. Devuelve { status:, body: }; status nil si no se pudo consultar.
  def self.probe_models(api_key, base_url)
    response = connection.get("#{api_base(base_url)}/models") do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
    end
    { status: response.status, body: response.body }
  rescue Faraday::Error => e
    { status: nil, body: e.message }
  end

  # Compat: booleano usado por pruebas/otros llamadores.
  def self.chat_completions_ok?(api_key, base_url)
    chat_completions_result(api_key, base_url).valid?
  end

  # Petición mínima a /v1/chat/completions. La key es válida si el proveedor NO responde 401
  # (un 400/404/422 significa "la key pasó; el body/modelo es lo que objeta", aceptable para
  # validar credenciales). Devuelve un Result con el código y mensaje reales del proveedor.
  def self.chat_completions_result(api_key, base_url)
    response = connection.post("#{api_base(base_url)}/chat/completions") do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
      req.headers['Content-Type'] = 'application/json'
      req.body = { model: 'gpt-4.1-mini', messages: [{ role: 'user', content: 'ping' }], max_tokens: 1 }.to_json
    end
    if response.status == 401
      Result.new(valid: false, code: 401, message: provider_error_message(response) || 'La API key fue rechazada (401).')
    else
      Result.new(valid: true, code: response.status, message: 'Conectado.')
    end
  rescue Faraday::Error => e
    Rails.logger.warn("[openai-key-validator] chat probe #{e.class}: #{e.message}")
    Result.new(valid: true, code: nil, message: "No se pudo verificar (#{e.class}); se acepta provisionalmente.")
  end

  # Mensaje de error del proveedor OpenAI-compatible ({"error":{"message":...}}), si vino.
  def self.provider_error_message(response)
    error_message_from_body(response.body)
  end

  def self.error_message_from_body(body)
    parsed = if body.is_a?(String)
               begin
                 JSON.parse(body)
               rescue StandardError
                 nil
               end
             else
               body
             end
    parsed.is_a?(Hash) ? parsed.dig('error', 'message').presence : nil
  end

  def self.openai_error_message(models)
    error_message_from_body(models[:body]).presence || 'OpenAI rechazó la API key (401).'
  end

  def self.connection
    Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS
    end
  end

  # El endpoint sale SOLO del base_url de ESTA integración (por cuenta). No depende de
  # Captain ni de ninguna InstallationConfig global. Si la cuenta no puso base_url, se usa
  # OpenAI oficial como último recurso.
  def self.api_base(base_url = nil)
    endpoint = base_url.presence || 'https://api.openai.com/'
    endpoint = endpoint.strip.chomp('/')
    endpoint.end_with?('/v1') ? endpoint : "#{endpoint}/v1"
  end
end
