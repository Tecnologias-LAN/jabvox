class SuperAdmin::AccountAutomationsController < SuperAdmin::ApplicationController
  # Credencial ENTRANTE (API key de la cuenta): update_api_key y test_connection.
  include SuperAdmin::AccountAutomationsApiKey
  # Reintento a prueba de fallos de las operaciones remotas (cola jabvox_automations).
  include SuperAdmin::AccountAutomationsRetry

  before_action :fetch_account
  before_action :fetch_config

  # rubocop:disable Rails/I18nLocaleTexts
  def index
    # Se calcula también con el módulo apagado, para ver con qué identidad se
    # conectará la cuenta antes de activar nada.
    load_user_selection

    if @config.enabled?
      service = Automations::ProvisioningService.new(@account)
      @remote_status = service.remote_status
      @module_status = service.module_status
    end

    # Derivado en cada visita: un `ok` histórico no debe sobrevivir a que el usuario
    # elegido deje de ser administrador.
    @state = state_service.recalculate!(remote_result: @remote_status)
  end

  # Guarda el usuario y aprovisiona en la misma operación: guardar sin reenviar el
  # token dejaría a Jabvox y Automations discrepando, que es peor que un fallo visible.
  def update_user
    return redirect_with_alert('El módulo debe estar activo para elegir el usuario de automatizaciones.') unless @config.enabled?

    user = find_selectable_user(params[:automations_user_id])
    return redirect_with_alert(@user_selection_error) if user.nil?

    previous_user = @config.automations_user
    persist_user_selection!(user, previous_user)
    provision_with_selected_user!(success_message: user_saved_message(user))
  end

  # Reenvía el token EXISTENTE, no lo regenera: el token es uno por usuario, así que
  # regenerarlo revocaría la credencial personal de esa persona.
  def reprovision
    return redirect_with_alert('El módulo debe estar activo para reaprovisionar.') unless @config.enabled?

    provision_with_selected_user!(
      success_message: 'Cuenta reaprovisionada: se ha reenviado a Automations el token del usuario seleccionado.'
    )
  end

  # Deshace solo la SELECCIÓN: no toca el token ni la membresía del usuario. Se
  # desactiva en remoto porque sin credencial válida no debe seguir ejecutando flujos.
  def remove_user
    previous_user = @config.automations_user
    return redirect_with_alert('Esta cuenta no tiene ningún usuario de automatizaciones seleccionado.') if previous_user.nil?

    result = Automations::ProvisioningService.new(@account).update_module!(max_flows: @config.max_flows, enabled: false)
    schedule_disable_retry(result)

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

  # Activar ya NO aprovisiona: deja la cuenta en pendiente_token y el
  # aprovisionamiento lo dispara la elección del usuario.
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
    elsif result.retryable?
      @config.update!(max_flows: max_flows_param)
      enqueue_background_retry('update_module', max_flows: max_flows_param, enabled: true)
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

  def user_token_service
    @user_token_service ||= Automations::UserTokenService.new(@account)
  end

  def state_service
    @state_service ||= Automations::StateService.new(@account)
  end

  # `current_super_admin` (Devise), no `current_user`: ese helper no existe en el
  # super admin, y de ahí que marcar el modelo como `audited` dejara el actor en NULL.
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

  # Se valida contra la CUENTA y no con `User.find`: sin esto, un POST manipulado
  # enviaría a Automations el token de cualquier usuario de la instalación.
  def find_selectable_user(raw_id)
    return reject_selection('Elige un usuario para las automatizaciones.') if raw_id.blank?

    membership = @account.account_users.find_by(user_id: raw_id)
    return reject_selection('Ese usuario no pertenece a esta cuenta.') if membership.nil?

    unless membership.administrator?
      return reject_selection('El usuario elegido debe ser administrador de la cuenta: un agente solo ve ' \
                              'las bandejas de las que es miembro y los flujos fallarían según la bandeja.')
    end

    user = membership.user
    if user.confirmed_at.blank?
      return reject_selection("#{user.email} no ha confirmado su cuenta todavía. La API de Jabvox rechaza " \
                              'los access tokens de usuarios sin confirmar, así que las automatizaciones darían 401.')
    end

    user
  end

  def reject_selection(message)
    @user_selection_error = message
    nil
  end

  # El rastro (quién, cuándo, IP) se guarda en la misma fila que la selección, para
  # que no pueda quedar un cambio de credencial sin actor conocido.
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

  # La orquestación vive en Automations::AccountProvisioner; aquí solo se traduce
  # el Result a mensaje y redirección.
  def provision_with_selected_user!(success_message:)
    result = Automations::AccountProvisioner.new(@account, @config).call

    if result.success?
      redirect_to super_admin_account_account_automations_path(@account), notice: success_message
    elsif result.retryable?
      enqueue_background_retry('provision')
    else
      redirect_with_alert("No se pudo aprovisionar: #{result.error} " \
                          'La selección de usuario se conserva: corrige el problema y pulsa "Reaprovisionar".')
    end
  end

  # Límite de flujos: vacío/blank => nil (ilimitado).
  def max_flows_param
    raw = params[:max_flows]
    raw.blank? ? nil : raw.to_i
  end

  # No aprovisiona ni toca `jabvox_advanced_automations_enabled_jabvox`: abrir el
  # módulo al cliente antes de tener credencial mostraría algo que no funciona.
  def enable!
    @config.update!(enabled: true, max_flows: max_flows_param, last_status: nil, last_error: nil)
    state_service.recalculate!

    redirect_to super_admin_account_account_automations_path(@account),
                notice: 'Módulo activado para esta cuenta. TODAVÍA NO está aprovisionado: elige el usuario ' \
                        'que prestará su token en "Usuario para automatizaciones" y pulsa ' \
                        '"Guardar y aprovisionar".'
  end

  # Ya NO se revoca ningún token: ahora pertenece a una persona y desactivar un
  # módulo no es motivo para romperle la app móvil. Corta la desactivación remota.
  def disable!
    result = Automations::ProvisioningService.new(@account).update_module!(max_flows: @config.max_flows, enabled: false)
    schedule_disable_retry(result)

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
