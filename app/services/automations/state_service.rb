# Máquina de estados de la integración Automations por cuenta.
#
# El estado se DERIVA en cada consulta, no solo se almacena: así un `ok` histórico no
# sobrevive a que falte la config global o a que el usuario elegido deje de servir.
class Automations::StateService
  # Enteros estables: son valores persistidos, se añaden al final y nunca en medio.
  STATES = {
    sin_config_global: 0,
    pendiente_token: 1,
    ok: 2,
    error_auth: 3
  }.freeze

  # Junto a los estados para que añadir uno no deje la vista pintando un hueco.
  PRESENTATION = {
    sin_config_global: {
      label: 'Sin configuración global',
      color: '#991b1b', background: '#fee2e2',
      detail: 'Falta configuración global de Automations (Service URL, Provision Key, ' \
              'URL del iframe o URL de callback). Hasta que esté completa, ninguna cuenta puede conectarse.'
    },
    pendiente_token: {
      label: 'Pendiente de usuario',
      color: '#854d0e', background: '#fef9c3',
      detail: 'El módulo está activo pero NO hay un usuario válido que preste su token. ' \
              'Las automatizaciones de esta cuenta NO funcionan todavía. ' \
              'Elige un usuario abajo y pulsa "Guardar y aprovisionar".'
    },
    ok: {
      label: 'Aprovisionado',
      color: '#166534', background: '#dcfce7',
      detail: 'Cuenta aprovisionada y credencial verificada contra Automations.'
    },
    error_auth: {
      label: 'Error de autenticación',
      color: '#991b1b', background: '#fee2e2',
      detail: 'Automations rechazó la credencial (401/403). Revisa la API key de la cuenta ' \
              'y que el token del usuario seleccionado siga siendo válido, y reaprovisiona.'
    }
  }.freeze

  def initialize(account)
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
  end

  # Solo la PRESENCIA de la config global, no su validez remota: el render de esta
  # página no debe depender de una llamada de red.
  def global_configured?
    Automations::ProvisioningService.configured?
  end

  # Devuelve la primera capa que falla, así que nunca da `ok` si falta una previa.
  # `remote_result` solo sirve para distinguir un 401/403 de un fallo de red.
  def recalculate(remote_result: nil)
    return :sin_config_global unless global_configured?

    config = @account.account_automation_config
    return :pendiente_token unless module_active?(config)
    return :pendiente_token unless Automations::UserTokenService.new(@account).validate!.valid?
    return :error_auth if auth_error?(config, remote_result)

    :ok
  end

  # `update_column` y solo si cambia: esto corre en el render (GET) y no debe generar
  # ruido de auditoría ni callbacks por el hecho de mirar la pantalla.
  def recalculate!(remote_result: nil)
    state = recalculate(remote_result: remote_result)
    config = @account.account_automation_config
    return state if config.nil?

    # El getter del enum devuelve el NOMBRE en string, no el entero: comparar contra
    # STATES.fetch daría siempre distinto y escribiría en cada render.
    if config.automations_state != state.to_s
      # rubocop:disable Rails/SkipsModelValidations
      config.update_column(:automations_state, STATES.fetch(state))
      # rubocop:enable Rails/SkipsModelValidations
    end

    state
  end

  private

  def module_active?(config)
    !config.nil? && config.enabled?
  end

  # Si no se ha comprobado nada (remote_result nil) se CONSERVA el error_auth guardado:
  # no haber preguntado no es prueba de que se haya arreglado.
  def auth_error?(config, remote_result)
    return true if auth_failure?(remote_result)

    remote_result.nil? && config.automations_state == :error_auth.to_s
  end

  # ProvisioningService ya formatea el error como texto, así que solo se puede mirar el
  # mensaje. Un fallo de red o un 5xx no es de credenciales y no degrada el estado.
  def auth_failure?(remote_result)
    return false if remote_result.nil?
    return false if remote_result.success?

    remote_result.error.to_s.match?(/respondió\s+40[13]\b/)
  end
end
