# Encapsulates the outbound HTTP calls to the external "Jabvox Automations"
# platform. Reads the global configuration from InstallationConfig via
# GlobalConfigService and never logs the master provisioning key.
#
# All network errors are rescued and returned as a Result so callers never
# blow up on connectivity issues.
class Automations::ProvisioningService
  OPEN_TIMEOUT = 5
  TIMEOUT = 15

  # Raised when the global module configuration is missing.
  ConfigurationError = Class.new(StandardError)

  Result = Struct.new(:success, :data, :error, keyword_init: true) do
    def success?
      success
    end
  end

  def initialize(account = nil)
    @account = account
  end

  # POST /provisioning/accounts — creates/activates the remote account.
  # max_flows nil => cupo ilimitado. advanced_automations_enabled habilita el
  # módulo "Automatizaciones Avanzadas" en la plataforma remota.
  #
  # jabvox_access_token: access token de un ADMINISTRADOR de esta cuenta. Viaja
  # server-to-server (protegido por la Provision Key + TLS) y Automation lo cifra
  # en reposo como su integración jabvox de la cuenta. NUNCA se registra en logs.
  # jabvox_base_url: URL interna por la que Automation vuelve a alcanzar este
  # Jabvox para leer/escribir datos de la cuenta. Se resuelve automáticamente
  # (ver .callback_base_url) si no se pasa explícitamente.
  def provision!(max_flows: nil, advanced_automations_enabled: true, jabvox_access_token: nil)
    require_account!
    response = client.post('provisioning/accounts') do |req|
      req.body = {
        chatwootAccountId: @account.id,
        name: @account.name,
        active: true,
        advancedAutomationsEnabled: advanced_automations_enabled,
        maxFlows: max_flows,
        # Auto-aprovisionamiento de credenciales: el usuario nunca las configura.
        jabvoxAccessToken: jabvox_access_token,
        jabvoxBaseUrl: self.class.callback_base_url
      }.compact
    end
    build_result(response)
  rescue Faraday::Error => e
    failure(network_error_message(e))
  end

  # PATCH /provisioning/accounts/:chatwootAccountId/module — actualiza el estado
  # del módulo y/o el límite de flujos sin re-aprovisionar la cuenta.
  def update_module!(max_flows:, enabled:)
    require_account!
    response = client.patch("provisioning/accounts/#{@account.id}/module") do |req|
      req.body = { advancedAutomationsEnabled: enabled, maxFlows: max_flows }
    end
    build_result(response)
  rescue Faraday::Error => e
    failure(network_error_message(e))
  end

  # DELETE /provisioning/accounts/:chatwootAccountId — deactivates the remote account.
  def deprovision!
    require_account!
    response = client.delete("provisioning/accounts/#{@account.id}")
    build_result(response)
  rescue Faraday::Error => e
    failure(network_error_message(e))
  end

  # GET /provisioning/status/:chatwootAccountId
  def remote_status
    require_account!
    response = client.get("provisioning/status/#{@account.id}")
    build_result(response)
  rescue Faraday::Error => e
    failure(network_error_message(e))
  end

  # GET /provisioning/accounts/:chatwootAccountId → { enabled, maxFlows, flowCount }
  # Uso actual del módulo (para mostrar consumo de cupo en el super admin).
  def module_status
    require_account!
    response = client.get("provisioning/accounts/#{@account.id}")
    build_result(response)
  rescue Faraday::Error => e
    failure(network_error_message(e))
  end

  # GET /health — public endpoint, no auth needed.
  def service_health
    response = health_client.get('health')
    build_result(response)
  rescue Faraday::Error => e
    failure(network_error_message(e))
  end

  def self.configured?
    base_url.present? && provision_key.present?
  end

  def self.base_url
    GlobalConfigService.load('AUTOMATIONS_SERVICE_URL', nil).to_s.strip
  end

  def self.provision_key
    GlobalConfigService.load('AUTOMATIONS_PROVISION_KEY', nil).to_s.strip
  end

  # URL interna por la que la plataforma Automation vuelve a alcanzar ESTA
  # instancia de Jabvox (para que sus nodos lean/escriban datos de la cuenta con
  # el access token aprovisionado).
  #
  # Orden de resolución:
  #   1. InstallationConfig 'AUTOMATIONS_JABVOX_CALLBACK_URL' (super admin).
  #   2. ENV['FRONTEND_URL'].
  #   3. Fallback de desarrollo: http://host.docker.internal:3000.
  #
  # IMPORTANTE (producción): debe ser la URL INTERNA por la que Automation
  # alcanza Jabvox. Si ambos corren en la misma VM, usa http://host.docker.internal:3000
  # (o la IP privada). NUNCA un dominio público cuando están juntos.
  def self.callback_base_url
    configured = GlobalConfigService.load('AUTOMATIONS_JABVOX_CALLBACK_URL', nil).to_s.strip
    return configured if configured.present?

    env_url = ENV['FRONTEND_URL'].to_s.strip
    return env_url if env_url.present?

    'http://host.docker.internal:3000'
  end

  private

  def require_account!
    raise ArgumentError, 'account is required' if @account.nil?
  end

  def build_result(response)
    if response.success?
      Result.new(success: true, data: response.body, error: nil)
    else
      failure(remote_error_message(response))
    end
  end

  def failure(message)
    Result.new(success: false, data: nil, error: message)
  end

  def remote_error_message(response)
    body = response.body
    detail = body.is_a?(Hash) ? (body['message'] || body['error']) : nil
    "Automations respondió #{response.status}#{detail ? ": #{detail}" : ''}"
  end

  def network_error_message(error)
    # Never surface secrets; only the error class/message from Faraday.
    "No se pudo conectar con Automations: #{error.message}"
  end

  def base_url
    url = self.class.base_url
    raise ConfigurationError, 'Automations no configurado (falta AUTOMATIONS_SERVICE_URL)' if url.blank?

    url
  end

  def provision_key
    key = self.class.provision_key
    raise ConfigurationError, 'Automations no configurado (falta AUTOMATIONS_PROVISION_KEY)' if key.blank?

    key
  end

  # Authenticated client used for provisioning endpoints.
  def client
    @client ||= build_connection(base_url) do |f|
      f.headers['X-Provision-Key'] = provision_key
    end
  end

  # Unauthenticated client used only for the public /health endpoint.
  def health_client
    @health_client ||= build_connection(base_url)
  end

  def build_connection(url)
    # Ensure a trailing slash so Faraday resolves relative paths against the
    # full base (e.g. ".../api/v1/health" instead of ".../api/health").
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
end
