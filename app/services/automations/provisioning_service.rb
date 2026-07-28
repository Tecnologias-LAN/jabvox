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
  #
  # SIEMPRE viaja con la Provision Key MAESTRA (master_client): la cuenta aún no
  # existe en la plataforma remota, así que todavía no puede tener API key propia.
  def provision!(max_flows: nil, advanced_automations_enabled: true, jabvox_access_token: nil)
    require_account!
    response = master_client.post('provisioning/accounts') do |req|
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
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # PATCH /provisioning/accounts/:chatwootAccountId/module — actualiza el estado
  # del módulo y/o el límite de flujos sin re-aprovisionar la cuenta.
  def update_module!(max_flows:, enabled:)
    require_account!
    response = client.patch("provisioning/accounts/#{@account.id}/module") do |req|
      req.body = { advancedAutomationsEnabled: enabled, maxFlows: max_flows }
    end
    build_result(response)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # DELETE /provisioning/accounts/:chatwootAccountId — deactivates the remote account.
  #
  # Va con la MAESTRA: desactivar una cuenta es una operación de plataforma, y
  # debe seguir siendo posible aunque la key propia de la cuenta esté revocada
  # o desincronizada (que es justo cuando más falta hace poder desactivarla).
  def deprovision!
    require_account!
    response = master_client.delete("provisioning/accounts/#{@account.id}")
    build_result(response)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # GET /provisioning/status/:chatwootAccountId
  def remote_status
    require_account!
    response = client.get("provisioning/status/#{@account.id}")
    build_result(response)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # GET /provisioning/accounts/:chatwootAccountId → { enabled, maxFlows, flowCount }
  # Uso actual del módulo (para mostrar consumo de cupo en el super admin).
  def module_status
    require_account!
    response = client.get("provisioning/accounts/#{@account.id}")
    build_result(response)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # "Probar conexión de ESTA cuenta": comprueba de punta a punta la credencial de
  # la cuenta contra la plataforma remota.
  #
  # POR QUÉ NO VALE EL /health GLOBAL: /health es público y no lleva ninguna
  # credencial, así que responde OK aunque la key de la cuenta esté revocada. Y
  # POR QUÉ ESTE ENDPOINT: /provisioning/accounts/:id es la operación por cuenta
  # que Jabvox ya usa, es de lectura (idempotente, no muta nada) y devuelve un
  # 401 si la credencial que enviamos no es válida — exactamente lo que hay que
  # diagnosticar.
  #
  # AISLAMIENTO: el resultado se devuelve como Result, nunca como excepción, y
  # todo el estado (cliente Faraday, credencial) es de ESTA instancia y de ESTA
  # cuenta. Una key inválida en una cuenta produce un fallo en su propia fila y
  # no toca ni la configuración global ni la conexión de las demás.
  def account_health
    require_account!
    response = client.get("provisioning/accounts/#{@account.id}")
    build_result(response)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Qué credencial se usará para las operaciones de esta cuenta: :account si
  # tiene API key propia, :master si cae a la Provision Key global.
  # La UI lo muestra para que el operador sepa qué está probando realmente.
  def credential_kind
    account_api_key.present? ? :account : :master
  end

  # GET /health — public endpoint, no auth needed.
  #
  # "Probar conexion" devolvia un 500 en los dos fallos de configuracion mas
  # probables, en vez de un mensaje util:
  #
  #   - Sin "Service URL": el metodo privado `base_url` lanza ConfigurationError,
  #     que no estaba capturado aqui.
  #   - Con una URL sin esquema (p.ej. "172.17.0.1:3001"): `Faraday.new` lanza
  #     `URI::BadURIError` ("both URI are relative"), que NO desciende de
  #     `Faraday::Error`, asi que tampoco lo capturaba el rescue existente.
  #
  # Ambos se traducen ahora a un resultado de fallo con el motivo concreto: este
  # boton existe justamente para diagnosticar la configuracion, asi que tiene que
  # explicar lo que falta en lugar de romperse.
  def service_health
    response = health_client.get('health')
    build_result(response)
  rescue Faraday::Error, ConfigurationError, URI::Error => e
    failure(call_error_message(e))
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
  # IMPORTANTE: quien usa esta URL es el CONTENEDOR de Automation, no este
  # proceso, así que no vale 127.0.0.1 (dentro del contenedor es él mismo) ni
  # `host.docker.internal`, que NO EXISTE en Docker para Linux (solo Mac/Windows).
  #
  # Si Jabvox escucha en todas las interfaces: la IP de docker0 (172.17.0.1).
  # Si Jabvox escucha SOLO en 127.0.0.1 (lo habitual con nginx delante), ninguna
  # IP interna lo alcanza desde el contenedor y hay que usar el dominio público,
  # que entra por nginx. Es un salto de red extra, pero es la única ruta que
  # existe con esa configuración.
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

  # Traduce a un mensaje accionable los tres fallos que puede dar una llamada al
  # servicio remoto. Los dos ultimos NO son `Faraday::Error` y antes subian como
  # excepcion, dejando un 500 en el super admin en vez de explicar que faltaba:
  #
  #   - ConfigurationError: falta Service URL o Provision Key.
  #   - URI::Error: la URL configurada no es valida (típicamente sin esquema, lo
  #     que hace que Faraday lance URI::BadURIError al construir la conexion).
  def call_error_message(error)
    case error
    when ConfigurationError
      "#{error.message}. Revisa la configuracion global de Automations " \
      '(Service URL, p.ej. http://172.17.0.1:3001/api/v1)'
    when URI::Error
      'La "Service URL" configurada no es una URL valida: debe incluir el esquema, ' \
      'p.ej. http://172.17.0.1:3001/api/v1'
    else
      network_error_message(error)
    end
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

  # API key PROPIA de la cuenta (nil si no tiene: cuentas ya aprovisionadas antes
  # de que existiera esta columna, o cuentas donde el operador no la ha pegado).
  #
  # Se lee de forma defensiva porque este servicio también se instancia sin
  # cuenta (para el /health global) y porque una cuenta puede no tener aún fila
  # de configuración.
  def account_api_key
    return nil if @account.nil?

    config = @account.account_automation_config
    config&.api_key_jabvox.presence
  end

  # Cliente autenticado para las operaciones de ESTA cuenta.
  #
  # ORDEN DE PRECEDENCIA (compatibilidad hacia atrás):
  #   1. API key propia de la cuenta -> header `X-Api-Key`.
  #   2. Si no tiene -> Provision Key maestra -> header `X-Provision-Key`.
  #
  # Se envía UNA credencial, no las dos: mandar también la maestra cuando existe
  # key de cuenta anularía el aislamiento, porque la plataforma remota aceptaría
  # la petición por la maestra y una key de cuenta revocada seguiría "funcionando"
  # — el operador nunca vería el fallo que intenta diagnosticar.
  #
  # `provision_key` solo se exige (y por tanto solo puede lanzar
  # ConfigurationError) en la rama 2: una cuenta con credencial propia no debe
  # depender de que la maestra esté configurada.
  def client
    @client ||= begin
      key = account_api_key
      build_connection(base_url) do |f|
        if key.present?
          f.headers['X-Api-Key'] = key
        else
          f.headers['X-Provision-Key'] = provision_key
        end
      end
    end
  end

  # Cliente que SIEMPRE usa la Provision Key maestra, ignorando la key de cuenta.
  #
  # Lo necesita el aprovisionamiento inicial: en ese momento la cuenta todavía no
  # existe en la plataforma remota, así que no puede tener una API key propia
  # (la key la emite Automations DESPUÉS de crear la cuenta). Crear/activar y
  # desactivar son operaciones de plataforma, no de tenant.
  def master_client
    @master_client ||= build_connection(base_url) do |f|
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
