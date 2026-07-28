class SuperAdmin::AccountAutomationsController < SuperAdmin::ApplicationController
  before_action :fetch_account
  before_action :fetch_config

  def index
    return unless @config.enabled?

    service = Automations::ProvisioningService.new(@account)
    @remote_status = service.remote_status
    @module_status = service.module_status
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

  # Devuelve el access token de un administrador de la cuenta (o nil si no hay).
  # Cada User tiene un AccessToken (has_one :access_token vía AccessTokenable),
  # el mismo que el dashboard muestra en Perfil → Access Token. Un super admin no
  # es agente de la cuenta, así que usamos el token de un administrador de ella.
  # El token es sensible: sólo se pasa server-to-server, nunca a logs ni al navegador.
  def account_admin_access_token
    admin = @account.account_users.where(role: :administrator).first&.user
    admin&.access_token&.token
  end

  # Límite de flujos: vacío/blank => nil (ilimitado).
  def max_flows_param
    raw = params[:max_flows]
    raw.blank? ? nil : raw.to_i
  end

  # rubocop:disable Rails/I18nLocaleTexts
  def enable!
    # Auto-aprovisionamiento del token: el super admin no configura credenciales.
    # Enviamos a Automation el access token de un ADMINISTRADOR de esta cuenta
    # para que sus nodos lean/escriban datos de ESA cuenta.
    access_token = account_admin_access_token
    if access_token.blank?
      @config.update!(enabled: false, last_status: 'error',
                      last_error: 'La cuenta no tiene un administrador con token de acceso')
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: 'No se pudo activar: la cuenta no tiene un administrador con token de acceso.'
      return
    end

    result = Automations::ProvisioningService.new(@account)
                                             .provision!(max_flows: max_flows_param,
                                                         advanced_automations_enabled: true,
                                                         jabvox_access_token: access_token)

    if result.success?
      @config.update!(
        enabled: true,
        max_flows: max_flows_param,
        remote_account_id: result.data.is_a?(Hash) ? result.data['id'] : nil,
        last_provisioned_at: Time.current,
        last_status: 'ok',
        last_error: nil
      )
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

    if result.success?
      @config.update!(enabled: false, last_status: 'ok', last_error: nil)
      @account.update!(jabvox_advanced_automations_enabled_jabvox: false)
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'Automations desactivado para esta cuenta'
    else
      @config.update!(enabled: false, last_status: 'error', last_error: result.error)
      @account.update!(jabvox_advanced_automations_enabled_jabvox: false)
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: "Automations desactivado localmente, pero el servicio remoto falló: #{result.error}"
    end
  end
  # rubocop:enable Rails/I18nLocaleTexts
end
