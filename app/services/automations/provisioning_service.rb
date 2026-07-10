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
  def provision!
    require_account!
    response = client.post('provisioning/accounts') do |req|
      req.body = { chatwootAccountId: @account.id, name: @account.name, active: true }
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
