class SuperAdmin::AccountAutomationsController < SuperAdmin::ApplicationController
  before_action :fetch_account
  before_action :fetch_config

  # rubocop:disable Rails/I18nLocaleTexts
  def index
    # Candidatos del selector y estado del usuario elegido. Se calcula SIEMPRE
    # (también con el módulo apagado) para que el operador vea con qué identidad
    # se conectará la cuenta ANTES de activar nada.
    load_user_selection

    if @config.enabled?
      service = Automations::ProvisioningService.new(@account)
      @remote_status = service.remote_status
      @module_status = service.module_status
    end

    # El estado se recalcula en cada visita: es DERIVADO, no un valor almacenado
    # que alguien tenga que acordarse de refrescar. Así un `ok` histórico no
    # sobrevive a que el usuario elegido deje de ser administrador.
    # Se le pasa @remote_status para poder distinguir un 401/403 (error_auth) de
    # un fallo de red cualquiera, que no debe degradar el estado.
    @state = state_service.recalculate!(remote_result: @remote_status)
  end

  # Guarda el USUARIO que presta su token a las automatizaciones y aprovisiona en
  # la MISMA operación.
  #
  # POR QUÉ EN UNA SOLA OPERACIÓN: guardar la selección sin reenviar el token
  # dejaría a Automations con la credencial anterior (la del usuario viejo, o
  # ninguna) mientras la UI diría que el usuario nuevo está configurado. Es el
  # mismo razonamiento que ya se aplicaba al reenvío del token: un estado donde
  # Jabvox y Automations discrepan es peor que un fallo visible.
  #
  # SUSTITUYE al antiguo `regenerate_service_token`, que se ha ELIMINADO: con un
  # usuario real, regenerar el token destruiría el token PERSONAL de esa persona y
  # le rompería la app móvil y sus integraciones propias.
  def update_user
    return redirect_with_alert('El módulo debe estar activo para elegir el usuario de automatizaciones.') unless @config.enabled?

    user = find_selectable_user(params[:automations_user_id])
    return redirect_with_alert(@user_selection_error) if user.nil?

    previous_user = @config.automations_user
    persist_user_selection!(user, previous_user)
    provision_with_selected_user!(success_message: user_saved_message(user))
  end

  # "Reaprovisionar": reenvía el token EXISTENTE del usuario seleccionado y la API
  # key de la cuenta en una sola operación.
  #
  # POR QUÉ ESTE BOTÓN Y NO "REGENERAR TOKEN": los access token de Jabvox son uno
  # por usuario (AccessTokenable: `has_one :access_token`) y no caducan.
  # Regenerarlo revocaría el token PERSONAL del usuario elegido, rompiéndole la
  # aplicación móvil y cualquier integración que tuviera montada por su cuenta.
  # Este panel no puede arrogarse esa decisión sobre la credencial de una persona.
  #
  # Así que "reaprovisionar" es idempotente y no destructivo: vuelve a enviar lo
  # que ya existe. Es la vía de recuperación cuando Automations perdió la
  # credencial, se restauró un backup antiguo del lado remoto, o el estado quedó
  # en error_auth por una API key de cuenta que ya se corrigió.
  def reprovision
    return redirect_with_alert('El módulo debe estar activo para reaprovisionar.') unless @config.enabled?

    provision_with_selected_user!(
      success_message: 'Cuenta reaprovisionada: se ha reenviado a Automations el token del usuario seleccionado.'
    )
  end

  # Quita el usuario seleccionado: la cuenta vuelve a `pendiente_token`.
  #
  # NO se toca el token del usuario (es suyo, ver #reprovision) ni su membresía en
  # la cuenta: solo se deshace LA SELECCIÓN. Lo único que se hace en remoto es
  # desactivar el módulo, porque una cuenta sin credencial válida no puede seguir
  # ejecutando flujos: si se dejara activa, Automations seguiría intentando
  # llamar con un token que ya no debería usar.
  def remove_user
    previous_user = @config.automations_user
    return redirect_with_alert('Esta cuenta no tiene ningún usuario de automatizaciones seleccionado.') if previous_user.nil?

    result = Automations::ProvisioningService.new(@account).update_module!(max_flows: @config.max_flows, enabled: false)

    @config.update!(automations_user_id: nil, automations_user_set_at: Time.current,
                    automations_user_set_by_id: audit_service.actor_id,
                    automations_user_set_ip: audit_service.remote_ip,
                    last_status: result.success? ? 'ok' : 'error',
                    last_error: result.success? ? nil : result.error)
    audit_service.log_user_change(previous_user: previous_user, new_user: nil)
    state_service.recalculate!

    redirect_to super_admin_account_account_automations_path(@account),
                notice: 'Usuario de automatizaciones retirado. Las automatizaciones de esta cuenta quedan ' \
                        'DETENIDAS hasta que se elija otro usuario. No se ha tocado el token personal de ' \
                        "#{previous_user.email}, que sigue siendo válido para esa persona."
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
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'No se hicieron cambios: se conserva la credencial actual de la cuenta.'
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
    # `render :index` no ejecuta la acción index, así que todo lo que la vista
    # necesita hay que calcularlo aquí también o se pintaría vacío.
    load_user_selection
    @state = state_service.recalculate!(remote_result: @account_health)
    render :index
  end

  # Activa o desactiva el módulo para esta cuenta.
  #
  # CAMBIO DE COMPORTAMIENTO (§7): ACTIVAR YA NO APROVISIONA. Antes, activar
  # creaba un usuario de servicio y aprovisionaba en el mismo clic, así que el
  # operador no podía revisar con qué identidad iba a conectarse la cuenta antes
  # de que ocurriera. Ahora activar solo deja la cuenta en `pendiente_token`; el
  # aprovisionamiento lo dispara la elección del usuario (#update_user).
  def toggle
    unless Automations::ProvisioningService.configured?
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: 'Automations no está configurado a nivel global. Configúralo primero.'
      return
    end

    @config.enabled? ? disable! : enable!
  end

  # Actualiza el límite de flujos sin re-aprovisionar la cuenta.
  def update_limit
    return redirect_with_alert('El módulo debe estar activo para cambiar el límite.') unless @config.enabled?

    result = Automations::ProvisioningService.new(@account).update_module!(max_flows: max_flows_param, enabled: true)

    if result.success?
      @config.update!(max_flows: max_flows_param, last_status: 'ok', last_error: nil)
      state_service.recalculate!
      redirect_to super_admin_account_account_automations_path(@account), notice: 'Límite de flujos actualizado'
    else
      @config.update!(last_status: 'error', last_error: result.error)
      state_service.recalculate!(remote_result: result)
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: "No se pudo actualizar el límite: #{result.error}"
    end
  end

  private

  def fetch_account
    @account = Account.find(params[:account_id])
  end

  def fetch_config
    @config = @account.account_automation_config || @account.build_account_automation_config
    @config.save! if @config.new_record?
  end

  # Resuelve QUÉ usuario presta su token y si sigue sirviendo.
  # Sustituye al antiguo `service_user_service`, que CREABA un usuario dedicado.
  def user_token_service
    @user_token_service ||= Automations::UserTokenService.new(@account)
  end

  def state_service
    @state_service ||= Automations::StateService.new(@account)
  end

  # Auditoría del cambio de usuario.
  #
  # `current_super_admin` es el helper de Devise que genera
  # `before_action :authenticate_super_admin!` del controlador base. NO existe
  # `current_user` en el super admin (de ahí que marcar el modelo como `audited`
  # dejara el actor en NULL); el precedente de uso está en
  # SuperAdmin::PushDiagnosticsController#log_super_admin_action. Ver la cabecera
  # de Automations::AuditService para el razonamiento completo.
  def audit_service
    @audit_service ||= Automations::AuditService.new(account: @account, actor: current_super_admin, request: request)
  end

  def load_user_selection
    @selectable_users = user_token_service.selectable_users
    @user_status = user_token_service.status
  end

  def redirect_with_alert(message)
    redirect_to super_admin_account_account_automations_path(@account), alert: message
  end

  # Valida que el id recibido corresponda a un usuario que REALMENTE puede ser
  # elegido para esta cuenta. Deja el motivo en @user_selection_error.
  #
  # POR QUÉ SE VALIDA CONTRA LA CUENTA Y NO SE HACE `User.find`: el id llega de un
  # `select` del formulario, y un `select` es una sugerencia del servidor, no una
  # garantía. Sin esta comprobación, un POST manipulado podría apuntar a CUALQUIER
  # usuario de la instalación —de otra cuenta, o un super admin— y esta pantalla
  # enviaría su access token a la plataforma remota. Es el paso que convierte una
  # referencia arbitraria en una autorización.
  #
  # Se exige ADMINISTRADOR: un `agent` solo ve las bandejas de las que es miembro,
  # así que los flujos fallarían de forma errática según en qué bandeja cayera la
  # conversación. Es el mismo criterio que aplicaba el usuario de servicio.
  def find_selectable_user(raw_id)
    if raw_id.blank?
      @user_selection_error = 'Elige un usuario para las automatizaciones.'
      return nil
    end

    membership = @account.account_users.find_by(user_id: raw_id)
    if membership.nil?
      @user_selection_error = 'Ese usuario no pertenece a esta cuenta.'
      return nil
    end

    unless membership.administrator?
      @user_selection_error = 'El usuario elegido debe ser administrador de la cuenta: un agente solo ve ' \
                              'las bandejas de las que es miembro y los flujos fallarían según la bandeja.'
      return nil
    end

    user = membership.user
    if user.confirmed_at.blank?
      @user_selection_error = "#{user.email} no ha confirmado su cuenta todavía. La API de Jabvox rechaza " \
                              'los access tokens de usuarios sin confirmar, así que las automatizaciones darían 401.'
      return nil
    end

    user
  end

  # Persiste la selección Y el rastro de auditoría en la misma transacción.
  #
  # Van JUNTOS a propósito: si se guardara el usuario y fallara la auditoría (o al
  # revés), quedaría un cambio de credencial sin actor conocido, que es
  # exactamente lo que la auditoría existe para evitar. La fila de `audits` se
  # escribe fuera de la transacción, dentro de AuditService, con su propio rescue:
  # es un canal secundario y no debe poder tumbar el guardado.
  def persist_user_selection!(user, previous_user)
    ActiveRecord::Base.transaction do
      @config.update!(
        automations_user_id: user.id,
        automations_user_set_at: Time.current,
        automations_user_set_by_id: audit_service.actor_id,
        automations_user_set_ip: audit_service.remote_ip
      )
    end
    audit_service.log_user_change(previous_user: previous_user, new_user: user)
  end

  def user_saved_message(user)
    "Usuario de automatizaciones guardado: #{user.name} (#{user.email}). " \
      'Se ha enviado su token a Automations.'
  end

  # Aprovisiona con el usuario seleccionado, VALIDÁNDOLO ANTES (requisito §5.2).
  #
  # La validación va aquí, en el paso común a #update_user y #reprovision, y no en
  # cada acción: el modo de fallo esperado es que la selección envejezca mal
  # (la persona sale de la empresa, se degrada a agente, se le retira de la
  # cuenta), y eso puede haber pasado entre que se eligió y que se reaprovisiona.
  # Sin esta comprobación, el síntoma sería un 401 opaco desde Automations.
  def provision_with_selected_user!(success_message:)
    validation = user_token_service.validate!
    unless validation.valid?
      @config.update!(last_status: 'error', last_error: validation.message)
      state_service.recalculate!
      return redirect_with_alert("No se pudo aprovisionar: #{validation.message}")
    end

    token = user_token_service.ensure_token!
    if token.blank?
      @config.update!(last_status: 'error', last_error: 'No se pudo obtener el access token del usuario seleccionado.')
      state_service.recalculate!
      return redirect_with_alert('No se pudo obtener el access token del usuario seleccionado. Inténtalo de nuevo.')
    end

    send_provision!(token, success_message)
  end

  # Envía a Automations el token del usuario y la API key de la cuenta en UNA
  # operación (requisito §5.2 del botón de reaprovisionar).
  #
  # `provision!` es un upsert por chatwootAccountId (ver ProvisionAccountDto del
  # repo de Automations), así que actualiza la cuenta existente sin crear nada
  # nuevo, y va por `master_client` (Provision Key maestra) porque el endpoint
  # remoto está protegido por ProvisioningKeyGuard, que exige `X-Provision-Key`.
  # Es lo correcto para una recuperación: si la key propia de la cuenta estuviera
  # revocada, un reenvío autenticado con ella fallaría — y estos botones existen
  # precisamente para cuando la cuenta está rota.
  def send_provision!(token, success_message)
    result = Automations::ProvisioningService
             .new(@account)
             .provision!(max_flows: @config.max_flows,
                         advanced_automations_enabled: true,
                         jabvox_access_token: token)

    if result.success?
      persist_successful_provision!(result)
      @account.update!(jabvox_advanced_automations_enabled_jabvox: true)
      state_service.recalculate!(remote_result: result)
      redirect_to super_admin_account_account_automations_path(@account), notice: success_message
    else
      # La selección SE CONSERVA aunque el envío falle: el usuario elegido es una
      # decisión del operador y no debe deshacerse por un fallo de red. El estado
      # refleja el problema y el botón "Reaprovisionar" permite reintentar.
      @config.update!(last_status: 'error', last_error: result.error)
      state_service.recalculate!(remote_result: result)
      redirect_with_alert("No se pudo aprovisionar en Automations: #{result.error}. " \
                          'El usuario seleccionado se ha guardado: pulsa "Reaprovisionar" cuando el ' \
                          'servicio remoto responda.')
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
      redirect_with_alert('No se pudo guardar la credencial: debe tener el formato jbx_ seguido de 32 caracteres ' \
                          'hexadecimales, tal como la devuelve el panel de Automations.')
    end
  end

  # Persiste el resultado de un aprovisionamiento correcto.
  def persist_successful_provision!(result)
    @config.update!(
      enabled: true,
      remote_account_id: result.data.is_a?(Hash) ? result.data['id'] : nil,
      last_provisioned_at: Time.current,
      last_status: 'ok',
      last_error: nil
    )
  end

  # Activar el módulo: NO aprovisiona (§7).
  #
  # Deja la cuenta en `pendiente_token` y lo dice. El aviso de la pantalla es
  # PERSISTENTE (AccountAutomationConfig#pending_user_warning?), no solo este
  # flash: un toast desaparece al recargar y esta es justo la situación que no
  # debe poder olvidarse — módulo activo y automatizaciones paradas.
  #
  # Tampoco se toca `jabvox_advanced_automations_enabled_jabvox` aquí: ese flag
  # abre el módulo en el dashboard del cliente, y abrirlo antes de que haya
  # credencial mostraría al usuario final un módulo que no puede funcionar. Se
  # activa al aprovisionar con éxito (ver #send_provision!).
  def enable!
    @config.update!(enabled: true, max_flows: max_flows_param, last_status: nil, last_error: nil)
    state_service.recalculate!

    redirect_to super_admin_account_account_automations_path(@account),
                notice: 'Módulo activado para esta cuenta. TODAVÍA NO está aprovisionado: elige el usuario ' \
                        'que prestará su token en "Usuario para automatizaciones" y pulsa ' \
                        '"Guardar y aprovisionar".'
  end

  # Desactivar el módulo.
  #
  # CAMBIO IMPORTANTE respecto al flujo anterior: ya NO se revoca ningún token.
  # Antes se destruía el access token del usuario de servicio, que era una
  # credencial nuestra. Ahora el token pertenece a una PERSONA y destruirlo le
  # rompería la app móvil y sus integraciones propias; desactivar el módulo de una
  # cuenta no es motivo para revocarle la credencial personal a nadie.
  #
  # Lo que corta el acceso es la desactivación en el lado remoto: Automations deja
  # de ejecutar flujos de esta cuenta. La SELECCIÓN se conserva para que reactivar
  # no obligue a volver a elegir, y el estado pasa a `pendiente_token` por no
  # estar el módulo activo.
  def disable!
    result = Automations::ProvisioningService.new(@account).update_module!(max_flows: @config.max_flows, enabled: false)

    @config.update!(enabled: false,
                    last_status: result.success? ? 'ok' : 'error',
                    last_error: result.success? ? nil : result.error)
    @account.update!(jabvox_advanced_automations_enabled_jabvox: false)
    state_service.recalculate!

    if result.success?
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'Automations desactivado para esta cuenta. No se ha revocado ningún token personal: ' \
                          'lo que detiene los flujos es la desactivación en la plataforma remota.'
    else
      redirect_with_alert('Automations desactivado localmente, pero el servicio remoto falló: ' \
                          "#{result.error}. La plataforma remota puede seguir ejecutando flujos de esta " \
                          'cuenta hasta que la desactivación se aplique: reintenta el desactivado.')
    end
  end
  # rubocop:enable Rails/I18nLocaleTexts
end
