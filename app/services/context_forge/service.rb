# frozen_string_literal: true

# Cliente HTTP de ContextForge (IBM MCP Gateway). Aprovisiona por cuenta e idempotente:
# team → MCPs → virtual server → scoped token. Errores de red -> Result (no revienta).
# Nunca registra la admin key ni el scoped token. PATHS centralizados para adaptar versión.
class ContextForge::Service
  OPEN_TIMEOUT = 5
  TIMEOUT = 30 # aprovisionar puede tardar (crea recursos remotos)

  ConfigurationError = Class.new(StandardError)

  # Paths de la API admin de ContextForge. Centralizados para adaptarlos a la versión.
  PATHS = {
    verify: 'health',
    teams: 'teams',
    servers: 'servers',            # virtual servers (agrupan MCPs)
    gateways: 'gateways',          # MCP servers federados (backend MCP)
    tokens: 'tokens',
    cron: 'cron/jobs'              # cron jobs de Hermes (scoped por token de cuenta)
  }.freeze

  Result = Struct.new(:success, :data, :error, :status, keyword_init: true) do
    def success?
      success
    end
  end

  # === Config global (super admin) ===

  def self.configured?
    base_url.present? && admin_key.present?
  end

  def self.base_url
    GlobalConfigService.load('CONTEXTFORGE_SERVICE_URL', nil).to_s.strip
  end

  def self.admin_key
    GlobalConfigService.load('CONTEXTFORGE_ADMIN_KEY', nil).to_s.strip
  end

  def self.hermes_url
    GlobalConfigService.load('CONTEXTFORGE_HERMES_URL', nil).to_s.strip
  end

  # URL por la que Hermes/los MCP vuelven a alcanzar ESTE Jabvox (para MCPs que leen
  # datos de la cuenta). Igual resolución que Automations.
  def self.callback_base_url
    configured = GlobalConfigService.load('CONTEXTFORGE_JABVOX_CALLBACK_URL', nil).to_s.strip
    return configured if configured.present?

    ENV['FRONTEND_URL'].to_s.strip.presence || 'http://host.docker.internal:3000'
  end

  # === Operaciones de plataforma (usan la admin key maestra) ===

  # Prueba de conexión autenticada. La usa el botón "Probar conexión" del super admin.
  def verify_global_config
    return failure('ContextForge no está configurado (falta URL o admin key).') unless self.class.configured?

    resp = admin_client.get(PATHS[:verify])
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Crea (o reusa) el TEAM de una cuenta. Idempotente: si ya existe por external_id,
  # devuelve el existente.
  def ensure_team(account)
    external_id = team_external_id(account)
    existing = find_by_external_id(PATHS[:teams], external_id)
    return existing if existing.success? && existing.data.present?

    resp = admin_client.post(PATHS[:teams]) do |req|
      req.body = { name: "jabvox-account-#{account.id}", external_id: external_id,
                   description: "Jabvox account #{account.id} (#{account.name})" }
    end
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Registra un MCP server (gateway federado) en el team de la cuenta. Idempotente por name.
  # kind: 'analytics_db' | 'reports' | ... (define qué backend MCP se conecta).
  def ensure_mcp_server(account, team_id:, kind:, name:, config: {})
    external_id = mcp_external_id(account, kind)
    existing = find_by_external_id(PATHS[:gateways], external_id)
    return existing if existing.success? && existing.data.present?

    resp = admin_client.post(PATHS[:gateways]) do |req|
      req.body = {
        name: name, external_id: external_id, team_id: team_id, kind: kind,
        jabvox_account_id: account.id, jabvox_callback_url: self.class.callback_base_url,
        config: config
      }.compact
    end
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Crea (o reusa) el VIRTUAL SERVER que agrupa SOLO las MCPs de la cuenta. Idempotente.
  def ensure_virtual_server(account, team_id:, mcp_server_ids:)
    external_id = server_external_id(account)
    existing = find_by_external_id(PATHS[:servers], external_id)
    return update_virtual_server(existing.data['id'], mcp_server_ids) if existing.success? && existing.data.present?

    resp = admin_client.post(PATHS[:servers]) do |req|
      req.body = { name: "jabvox-account-#{account.id}", external_id: external_id,
                   team_id: team_id, associated_tools: mcp_server_ids }
    end
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Emite un TOKEN con alcance SOLO a un virtual server (permisos de la cuenta N).
  # Este es el token que usará el Consumer del Chat IA de la cuenta.
  def issue_scoped_token(account, team_id:, virtual_server_id:)
    resp = admin_client.post(PATHS[:tokens]) do |req|
      req.body = {
        name: "jabvox-account-#{account.id}-consumer",
        team_id: team_id,
        server_id: virtual_server_id,     # alcance: SOLO este virtual server
        scopes: ['tools:call', 'tools:list'],
        external_id: "jabvox-token-#{account.id}"
      }
    end
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Lista las tools/MCPs visibles CON un scoped token (lo que verá el Consumer).
  # Verifica el aislamiento: con el token de la cuenta N solo deben salir sus MCPs.
  def list_tools(scoped_token, base_url: nil)
    resp = scoped_client(scoped_token, base_url).get("#{PATHS[:servers]}/tools")
    build_result(resp)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Cron jobs de Hermes (con el SCOPED TOKEN de la cuenta): el módulo
  # ContextForge::Service::CronJobs (service/cron_jobs.rb) se incluye al final del archivo,
  # ya con la clase definida. Su helper hermes_scoped_client vive también en ese módulo.

  private

  def update_virtual_server(server_id, mcp_server_ids)
    resp = admin_client.put("#{PATHS[:servers]}/#{server_id}") do |req|
      req.body = { associated_tools: mcp_server_ids }
    end
    build_result(resp)
  end

  # Busca un recurso por su external_id (idempotencia). Devuelve Result con el objeto o nil.
  def find_by_external_id(path, external_id)
    resp = admin_client.get(path) do |req|
      req.params['external_id'] = external_id
    end
    result = build_result(resp)
    return result unless result.success?

    match = Array(result.data).find { |r| r.is_a?(Hash) && r['external_id'] == external_id }
    Result.new(success: true, data: match, status: resp.status)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # === identificadores estables por cuenta (idempotencia) ===
  def team_external_id(account) = "jabvox-team-#{account.id}"
  def server_external_id(account) = "jabvox-vs-#{account.id}"
  def mcp_external_id(account, kind) = "jabvox-mcp-#{account.id}-#{kind}"

  # === clientes HTTP ===

  # Cliente con la ADMIN KEY maestra (operaciones de plataforma).
  def admin_client
    @admin_client ||= begin
      raise ConfigurationError, 'ContextForge admin key ausente' if self.class.admin_key.blank?

      build_connection(require_base_url!) do |f|
        f.headers['Authorization'] = "Bearer #{self.class.admin_key}"
      end
    end
  end

  # Cliente con un SCOPED TOKEN de cuenta (para verificar aislamiento / listar tools).
  def scoped_client(token, base = nil)
    build_connection(base.presence || require_base_url!) do |f|
      f.headers['Authorization'] = "Bearer #{token}"
    end
  end

  def require_base_url!
    url = self.class.base_url
    raise ConfigurationError, 'ContextForge base URL ausente' if url.blank?

    url
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
    "ContextForge respondió #{response.status}#{": #{msg}" if msg.present?}"
  end

  def failure(message)
    Result.new(success: false, error: message)
  end

  # Mensaje de error de red SIN filtrar secretos.
  def call_error_message(error)
    case error
    when Faraday::TimeoutError then 'ContextForge no respondió a tiempo (timeout).'
    when Faraday::ConnectionFailed then 'No se pudo conectar con ContextForge.'
    when ConfigurationError then error.message
    else "Error al contactar ContextForge: #{error.class}"
    end
  end

  # Incluido aquí (no en el cuerpo de arriba) para que la clase ya esté definida cuando
  # Zeitwerk autoloadee el módulo anidado ContextForge::Service::CronJobs.
  include CronJobs
end
