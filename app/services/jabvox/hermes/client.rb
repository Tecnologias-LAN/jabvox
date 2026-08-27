# frozen_string_literal: true

# Cliente HTTP hacia el Hermes de UNA cuenta (por la red ZeroTier).
#
# Jabvox NUNCA aprovisiona ni crea MCPs: eso lo hace el Hermes Aprovisionador. Este cliente
# solo CONSUME el Hermes ya levantado de la cuenta con su SCOPED TOKEN:
#   - listar las tools/MCPs visibles (para mostrarlas en el Chat IA)
#   - gestionar los cron jobs de la cuenta (scoped por token → solo los suyos)
#
# El scoped token acota todo al Hermes de la cuenta N; con él es imposible tocar otra cuenta
# (Hermes responde 403). Nunca se registra el token en logs.
class Jabvox::Hermes::Client
  OPEN_TIMEOUT = 5
  TIMEOUT = 20

  ConfigurationError = Class.new(StandardError)

  # Paths del gateway de Hermes.
  PATHS = {
    tools: 'servers/tools',
    cron: 'cron/jobs'
  }.freeze

  Result = Struct.new(:success, :data, :error, :status, keyword_init: true) do
    def success? = success
  end

  # URL global del gateway de Hermes (fallback cuando el handoff de la cuenta no trae una
  # URL propia). Es SOLO la dirección de red del Hermes; no es config de ContextForge.
  def self.hermes_url
    GlobalConfigService.load('HERMES_GATEWAY_URL', nil).to_s.strip
  end

  # Lista las tools/MCPs visibles con el scoped token de la cuenta (verifica aislamiento).
  def list_tools(scoped_token, base_url: nil)
    resp = scoped_client(scoped_token, base_url).get(PATHS[:tools])
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # --- Cron jobs de Hermes (scoped por token: solo los de la cuenta) ---

  def list_cron_jobs(scoped_token, base_url: nil)
    resp = scoped_client(scoped_token, base_url).get(PATHS[:cron])
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  def create_cron_job(scoped_token, attrs, base_url: nil)
    resp = scoped_client(scoped_token, base_url).post(PATHS[:cron]) { |r| r.body = attrs }
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  def set_cron_job_enabled(scoped_token, job_id, enabled, base_url: nil)
    resp = scoped_client(scoped_token, base_url).patch("#{PATHS[:cron]}/#{job_id}") do |r|
      r.body = { enabled: enabled }
    end
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Elimina un cron job DE HERMES (no un registro de Jabvox): gestionar sus propios crons es
  # parte normal del cliente y no viola la política de no-borrado sobre datos de Jabvox.
  def delete_cron_job(scoped_token, job_id, base_url: nil)
    resp = scoped_client(scoped_token, base_url).delete("#{PATHS[:cron]}/#{job_id}")
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  private

  # Cliente hacia el Hermes de la cuenta con su scoped token. `base` es la hermes_url del
  # handoff de la cuenta (preferida) o la global.
  def scoped_client(token, base = nil)
    url = base.presence || self.class.hermes_url
    raise ConfigurationError, 'Hermes URL ausente' if url.blank?

    build_connection(url) { |f| f.headers['Authorization'] = "Bearer #{token}" }
  end

  def build_connection(url)
    normalized = url.end_with?('/') ? url : "#{url}/"
    Faraday.new(url: normalized) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.options.open_timeout = OPEN_TIMEOUT
      f.options.timeout = TIMEOUT
      yield f if block_given?
      f.adapter Faraday.default_adapter
    end
  end

  def build_result(response)
    if response.success?
      Result.new(success: true, data: response.body, status: response.status)
    else
      Result.new(success: false, error: remote_error(response), status: response.status)
    end
  end

  def remote_error(response)
    body = response.body
    msg = body.is_a?(Hash) ? (body['error'] || body['message'] || body['detail']) : nil
    "Hermes respondió #{response.status}#{": #{msg}" if msg.present?}"
  end

  def failure(message)
    Result.new(success: false, error: message)
  end

  def call_error_message(error)
    case error
    when Faraday::TimeoutError then 'Hermes no respondió a tiempo (timeout).'
    when Faraday::ConnectionFailed then 'No se pudo conectar con el Hermes de la cuenta.'
    when ConfigurationError then error.message
    else "Error al contactar Hermes: #{error.class}"
    end
  end
end
