class SuperAdmin::AutomationsConfigsController < SuperAdmin::ApplicationController
  ALLOWED_CONFIGS = %w[AUTOMATIONS_SERVICE_URL AUTOMATIONS_FRONTEND_URL AUTOMATIONS_PROVISION_KEY
                       AUTOMATIONS_SSO_SECRET AUTOMATIONS_JABVOX_CALLBACK_URL].freeze

  # Secretos que nunca se re-renderizan: un envio en blanco significa
  # "conservar el valor actual", no "borrarlo".
  MASKED_SECRETS = %w[AUTOMATIONS_PROVISION_KEY AUTOMATIONS_SSO_SECRET].freeze

  # Las tres claves que contienen URLs, con la etiqueta del campo en la pantalla
  # para que el mensaje de error diga cuál hay que corregir.
  URL_CONFIGS = {
    'AUTOMATIONS_SERVICE_URL' => 'Service URL',
    'AUTOMATIONS_FRONTEND_URL' => 'Frontend URL (iframe)',
    'AUTOMATIONS_JABVOX_CALLBACK_URL' => 'Jabvox Callback URL'
  }.freeze

  before_action :load_app_config

  def show; end

  def create
    # Las URLs se validan ANTES de escribir nada: si una es inválida se rechaza el
    # envío completo, para no dejar media configuración guardada.
    errors = url_errors
    errors = persist_configs! if errors.empty?

    if errors.any?
      redirect_to super_admin_automations_config_path, alert: errors.join(', ')
    else
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_automations_config_path, notice: 'Configuración de Automations actualizada'
      # rubocop:enable Rails/I18nLocaleTexts
    end
  end

  # PRUEBA DE CONEXIÓN AUTENTICADA (POST /provisioning/verify).
  #
  # Antes esto llamaba a `service_health` (GET /health), que es PÚBLICO: respondía
  # "correcto" con la Provision Key mal escrita, vacía o de otra instalación. El
  # fallo real aparecía mucho después, como un 401 al aprovisionar en producción.
  #
  # Ahora se envía la Provision Key y las tres URLs. Si la clave no es válida, la
  # plataforma remota responde 401 y aquí se ve el fallo. Y como esta llamada es la
  # que REGISTRA la aprobación de la configuración global, sin ella la plataforma
  # remota rechaza con 424 cualquier alta de credenciales de cuenta: pulsar este
  # botón es lo que desbloquea el módulo, no solo un diagnóstico.
  #
  # La ruta sigue llamándose `health` para no romper el enlace ni el marcador que
  # el operador pueda tener guardado.
  def health
    @health = Automations::ProvisioningService.new.verify_global_config
    render :show
  end

  private

  # Guarda los valores permitidos y devuelve los errores de validación del modelo
  # (vacío si todo fue bien).
  def persist_configs!
    errors = []
    (params['app_config'] || {}).each do |key, value|
      next unless ALLOWED_CONFIGS.include?(key)
      next if skip_blank_secret?(key, value)

      i = InstallationConfig.where(name: key).first_or_create(value: value, locked: false)
      i.value = value
      errors.concat(i.errors.full_messages) unless i.save
    end
    errors
  end

  # Valida las tres URLs ANTES de guardar. Se rechaza el envío completo si alguna
  # es inválida, en vez de persistir un valor que rompería la integración.
  #
  # El caso que de verdad importa es `javascript:`: la Frontend URL termina en el
  # `src` de un iframe del panel, así que un esquema arbitrario aquí es XSS, no
  # solo una URL que no funciona. Confiar en el 400 de la plataforma remota no
  # bastaría, porque ese 400 llega DESPUÉS de haberlo guardado.
  #
  # Solo se validan las claves PRESENTES en el envío: el formulario manda las tres
  # siempre, pero así un envío parcial (o futuro) no falla por campos que no toca.
  # Nota: un valor en blanco sí se rechaza si viene en el envío, porque las tres
  # URLs son obligatorias para que la prueba de conexión pueda aprobar nada.
  def url_errors
    submitted = params['app_config'] || {}
    URL_CONFIGS.filter_map do |key, label|
      next unless submitted.key?(key)

      Automations::UrlValidator.url_error(submitted[key], label)
    end
  end

  # ref: https://github.com/rubocop/rubocop/issues/7767
  # rubocop:disable Style/HashTransformValues
  def load_app_config
    @app_config = InstallationConfig.where(name: ALLOWED_CONFIGS)
                                    .pluck(:name, :serialized_value)
                                    .map { |name, serialized_value| [name, serialized_value['value']] }
                                    .to_h
  end
  # rubocop:enable Style/HashTransformValues

  # Los secretos enmascarados nunca se re-renderizan, asi que un envio en blanco
  # significa "conservar el valor actual" en vez de "borrarlo".
  def skip_blank_secret?(key, value)
    MASKED_SECRETS.include?(key) && value.blank?
  end
end
