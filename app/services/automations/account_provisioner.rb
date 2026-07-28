# Aprovisiona una cuenta con el usuario seleccionado: valida, obtiene el token, lo
# envía a Automations y persiste el resultado. Compartido por guardar y reaprovisionar.
class Automations::AccountProvisioner
  Result = Struct.new(:success, :error, :state, keyword_init: true) do
    def success?
      success
    end
  end

  def initialize(account, config)
    @account = account
    @config = config
  end

  # Se valida SIEMPRE, también al reaprovisionar: la selección puede haber envejecido
  # mal desde que se eligió (la persona se fue, se degradó a agente, se le retiró).
  def call
    validation = user_token_service.validate!
    return failure(validation.message) unless validation.valid?

    token = user_token_service.ensure_token!
    return failure('No se pudo obtener el access token del usuario seleccionado. Inténtalo de nuevo.') if token.blank?

    send_provision(token)
  end

  private

  def user_token_service
    @user_token_service ||= Automations::UserTokenService.new(@account)
  end

  def state_service
    @state_service ||= Automations::StateService.new(@account)
  end

  # `provision!` es un upsert por chatwootAccountId y va con la Provision Key maestra,
  # que es la que exige el guard remoto: correcto para recuperar una cuenta rota.
  def send_provision(token)
    result = Automations::ProvisioningService
             .new(@account)
             .provision!(max_flows: @config.max_flows,
                         advanced_automations_enabled: true,
                         jabvox_access_token: token)

    result.success? ? persist_success(result) : persist_remote_failure(result)
  end

  def persist_success(result)
    @config.update!(
      enabled: true,
      remote_account_id: result.data.is_a?(Hash) ? result.data['id'] : nil,
      last_provisioned_at: Time.current,
      last_status: 'ok',
      last_error: nil
    )
    # El módulo se abre al cliente solo cuando hay credencial funcionando.
    @account.update!(jabvox_advanced_automations_enabled_jabvox: true)
    Result.new(success: true, error: nil, state: state_service.recalculate!(remote_result: result))
  end

  # La selección se CONSERVA aunque falle el envío: es una decisión del operador y
  # "Reaprovisionar" permite reintentar sin volver a elegir.
  def persist_remote_failure(result)
    @config.update!(last_status: 'error', last_error: result.error)
    Result.new(success: false, error: result.error, state: state_service.recalculate!(remote_result: result))
  end

  # Fallo local: no se ha llamado a Automations, así que el estado caerá a pendiente_token.
  def failure(message)
    @config.update!(last_status: 'error', last_error: message)
    Result.new(success: false, error: message, state: state_service.recalculate!)
  end
end
