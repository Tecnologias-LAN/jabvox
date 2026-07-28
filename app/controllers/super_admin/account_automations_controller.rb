class SuperAdmin::AccountAutomationsController < SuperAdmin::ApplicationController
  before_action :fetch_account
  before_action :fetch_config

  def index
    # Estado del usuario de servicio: se calcula SIEMPRE (también con el módulo
    # apagado) para que el operador pueda ver qué identidad quedó tras una
    # desactivación y cuál se usará al reactivar. Es solo lectura: no crea nada.
    @service_user_status = service_user_service.status

    return unless @config.enabled?

    service = Automations::ProvisioningService.new(@account)
    @remote_status = service.remote_status
    @module_status = service.module_status
  end

  # Regenera el access token del usuario de servicio y lo reenvía a Automations
  # en la MISMA operación.
  #
  # POR QUÉ EN UNA SOLA OPERACIÓN: si solo se regenerara en Jabvox, Automations
  # seguiría guardando el token viejo (ya destruido) y la cuenta pasaría de
  # "roto de forma diagnosticable" a "roto en silencio". Y si el reenvío falla,
  # se registra en last_error y se avisa, porque en ese momento la cuenta está
  # peor que antes y el operador tiene que saberlo para reintentar.
  #
  # Es la vía de recuperación del caso 401: token filtrado, rotado a mano o
  # desincronizado entre las dos plataformas.
  def regenerate_service_token
    unless @config.enabled?
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: 'El módulo debe estar activo para regenerar el token del usuario de servicio.'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    token = service_user_service.regenerate_token!
    resend_service_token(token)
  rescue ActiveRecord::RecordInvalid => e
    @config.update(last_status: 'error', last_error: "No se pudo regenerar el token: #{e.message}")
    redirect_to super_admin_account_account_automations_path(@account),
                alert: "No se pudo regenerar el token del usuario de servicio: #{e.message}"
  end

  # Guarda la API key PROPIA de esta cuenta (la que se regenera en el panel
  # /admin de Automations y se pega aquí).
  #
  # SEMÁNTICA DEL CAMPO VACÍO: igual que MASKED_SECRETS/skip_blank_secret? en
  # SuperAdmin::AutomationsConfigsController, un envío en blanco significa
  # "conservar la actual", NO "borrarla". La key nunca se re-renderiza en el
  # formulario, así que interpretar el blanco como borrado haría que cualquier
  # guardado de otro campo dejara la cuenta sin credencial. Para borrarla de
  # forma explícita existe el botón "Quitar" (parámetro remove_api_key).
  def update_api_key
    if params[:remove_api_key].present?
      @config.assign_api_key(nil)
      persist_api_key!('Credencial de la cuenta eliminada. Esta cuenta volverá a usar la Provision Key maestra.')
      return
    end

    raw = params[:api_key].to_s.strip
    if raw.blank?
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'No se hicieron cambios: se conserva la credencial actual de la cuenta.'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    @config.assign_api_key(raw)
    persist_api_key!('Credencial de la cuenta guardada. Usa "Probar conexión de esta cuenta" para verificarla.')
  end

  # "Probar conexión de ESTA cuenta": usa la credencial de la cuenta (o la
  # maestra si no tiene propia) contra la plataforma remota y muestra el
  # resultado. No modifica nada en remoto.
  #
  # AISLAMIENTO: el resultado se guarda en la fila de ESTA cuenta
  # (last_status/last_error) y no toca ninguna configuración global, así que una
  # cuenta con key inválida no degrada a las demás ni al health global.
  def test_connection
    service = Automations::ProvisioningService.new(@account)
    @account_health = service.account_health
    @credential_kind = service.credential_kind

    # El diagnóstico se persiste para que quede rastro de cuándo falló y por qué,
    # visible al recargar la página.
    @config.update(last_status: @account_health.success? ? 'ok' : 'error',
                   last_error: @account_health.success? ? nil : @account_health.error)

    @remote_status = @account_health
    @module_status = service.module_status if @config.enabled?
    # `render :index` no ejecuta la acción index, así que el estado del usuario de
    # servicio hay que calcularlo aquí también o la vista lo pintaría vacío.
    @service_user_status = service_user_service.status
    render :index
  end

  # Activates or deactivates the Automations connection for this account by
  # provisioning/deprovisioning the remote account on the Automations platform.
  def toggle
    unless Automations::ProvisioningService.configured?
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: 'Automations no está configurado a nivel global. Configúralo primero.'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    @config.enabled? ? disable! : enable!
  end

  # Actualiza el límite de flujos sin re-aprovisionar la cuenta.
  def update_limit
    unless @config.enabled?
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: 'El módulo debe estar activo para cambiar el límite.'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    result = Automations::ProvisioningService.new(@account).update_module!(max_flows: max_flows_param, enabled: true)

    # rubocop:disable Rails/I18nLocaleTexts
    if result.success?
      @config.update!(max_flows: max_flows_param, last_status: 'ok', last_error: nil)
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'Límite de flujos actualizado'
    else
      @config.update!(last_status: 'error', last_error: result.error)
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: "No se pudo actualizar el límite: #{result.error}"
    end
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def fetch_account
    @account = Account.find(params[:account_id])
  end

  def fetch_config
    @config = @account.account_automation_config || @account.build_account_automation_config
    @config.save! if @config.new_record?
  end

  # Servicio del USUARIO DE SERVICIO de esta cuenta (identidad propia de las
  # automatizaciones). Sustituye al antiguo `account_admin_access_token`, que
  # tomaba prestado el token del primer administrador humano que encontrara.
  def service_user_service
    @service_user_service ||= Automations::ServiceUserService.new(@account)
  end

  # Reenvía a Automations el token recién regenerado reutilizando el mismo
  # `provision!` del alta: es un upsert por chatwootAccountId (ver
  # ProvisionAccountDto), así que actualiza la credencial de la cuenta existente
  # sin crear nada nuevo. Se conserva max_flows para no perder el cupo ya fijado.
  #
  # POR QUÉ SIRVE AQUÍ AUNQUE LA CUENTA TENGA API KEY PROPIA: `provision!` va por
  # `master_client` (Provision Key maestra), y el endpoint remoto está protegido
  # por ProvisioningKeyGuard, que exige justamente `X-Provision-Key`. Es lo
  # correcto para una recuperación: si la key propia de la cuenta estuviera
  # revocada, un reenvío autenticado con ella fallaría — y este botón existe
  # precisamente para los casos en que la cuenta está rota.
  #
  def resend_service_token(token)
    result = Automations::ProvisioningService
             .new(@account)
             .provision!(max_flows: @config.max_flows,
                         advanced_automations_enabled: true,
                         jabvox_access_token: token)

    if result.success?
      @config.update!(last_provisioned_at: Time.current, last_status: 'ok', last_error: nil)
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'Token del usuario de servicio regenerado y reenviado a Automations. ' \
                          'El token anterior ya no es válido.'
    else
      # El token viejo YA está destruido, así que la cuenta está sin credencial
      # válida en el lado remoto hasta que el reenvío funcione. Se dice claramente.
      @config.update!(last_status: 'error',
                      last_error: "Token regenerado en Jabvox pero NO reenviado a Automations: #{result.error}")
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: 'Token regenerado en Jabvox, pero no se pudo reenviar a Automations: ' \
                         "#{result.error}. La cuenta seguirá fallando hasta que se reenvíe: vuelve a pulsar " \
                         '"Regenerar token" cuando el servicio remoto responda.'
    end
  end

  # Límite de flujos: vacío/blank => nil (ilimitado).
  def max_flows_param
    raw = params[:max_flows]
    raw.blank? ? nil : raw.to_i
  end

  # Guarda la credencial ya asignada al @config y redirige con el mensaje
  # correspondiente. Si el formato no valida (pegado truncado o con basura), se
  # avisa aquí en vez de dejar que la plataforma remota responda un 401 opaco.
  def persist_api_key!(success_message)
    if @config.save
      redirect_to super_admin_account_account_automations_path(@account), notice: success_message
    else
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: 'No se pudo guardar la credencial: debe tener el formato jbx_ seguido de 32 caracteres ' \
                         'hexadecimales, tal como la devuelve el panel de Automations.'
    end
  end

  # Garantiza el token del usuario de servicio, o nil si no se pudo (dejando ya
  # registrado el error y la redirección). Extraído de enable! para que el flujo
  # de activación se lea de un tirón.
  #
  # Se captura RecordInvalid porque el usuario de servicio se crea aquí y puede
  # fallar por validación (p.ej. el email ya está tomado por una persona). Sin
  # este rescate, el super admin vería un 500 en vez del motivo concreto.
  def ensure_service_token_or_fail
    service_user_service.ensure_token!
  rescue ActiveRecord::RecordInvalid => e
    @config.update!(enabled: false, last_status: 'error',
                    last_error: "No se pudo crear el usuario de servicio: #{e.message}")
    redirect_to super_admin_account_account_automations_path(@account),
                alert: "No se pudo activar: no se pudo crear el usuario de servicio (#{e.message})."
    nil
  end

  # Persiste el resultado de un aprovisionamiento correcto.
  def persist_successful_provision!(result)
    @config.update!(
      enabled: true,
      max_flows: max_flows_param,
      remote_account_id: result.data.is_a?(Hash) ? result.data['id'] : nil,
      last_provisioned_at: Time.current,
      last_status: 'ok',
      last_error: nil
    )
  end

  # rubocop:disable Rails/I18nLocaleTexts
  def enable!
    # Auto-aprovisionamiento del token: el super admin no configura credenciales.
    #
    # Se envía a Automations el access token del USUARIO DE SERVICIO de esta
    # cuenta, no el de un administrador humano. `ensure_token!` crea el usuario
    # si no existía y le garantiza un token, de forma IDEMPOTENTE: activar dos
    # veces no duplica usuarios ni tokens.
    #
    # POR QUÉ ESTO ARREGLA EL 401: antes se buscaba `access_token` de un admin
    # cualquiera y podía ser nil (usuarios creados antes del after_create de
    # AccessTokenable) o estar rotado. Ahora el token se garantiza en el momento
    # de aprovisionar, así que lo que se manda existe siempre y es válido.
    access_token = ensure_service_token_or_fail
    return if access_token.blank? # ensure_service_token_or_fail ya redirigió

    result = Automations::ProvisioningService.new(@account)
                                             .provision!(max_flows: max_flows_param,
                                                         advanced_automations_enabled: true,
                                                         jabvox_access_token: access_token)

    if result.success?
      persist_successful_provision!(result)
      # Mantiene el feature flag del dashboard alineado con el estado real.
      @account.update!(jabvox_advanced_automations_enabled_jabvox: true)
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'Automations activado para esta cuenta'
    else
      @config.update!(enabled: false, last_status: 'error', last_error: result.error)
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: "No se pudo activar Automations: #{result.error}"
    end
  end

  def disable!
    result = Automations::ProvisioningService.new(@account).update_module!(max_flows: @config.max_flows, enabled: false)

    # Revoca el acceso del usuario de servicio SIEMPRE, aunque la llamada remota
    # falle: si el módulo queda desactivado en Jabvox, su token no debe seguir
    # sirviendo. Se desactiva (token destruido + membresía retirada), NO se borra
    # el usuario, para no romper el histórico que apunta a él — ver el comentario
    # de Automations::ServiceUserService#deactivate_user!
    service_user_service.deactivate_user!

    if result.success?
      @config.update!(enabled: false, last_status: 'ok', last_error: nil)
      @account.update!(jabvox_advanced_automations_enabled_jabvox: false)
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'Automations desactivado para esta cuenta. El usuario de servicio queda desactivado ' \
                          '(sin token ni acceso) pero se conserva para no perder la trazabilidad del histórico.'
    else
      @config.update!(enabled: false, last_status: 'error', last_error: result.error)
      @account.update!(jabvox_advanced_automations_enabled_jabvox: false)
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: "Automations desactivado localmente (usuario de servicio revocado), pero el servicio remoto falló: #{result.error}"
    end
  end
  # rubocop:enable Rails/I18nLocaleTexts
end
