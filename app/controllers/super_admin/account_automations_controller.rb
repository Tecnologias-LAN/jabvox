class SuperAdmin::AccountAutomationsController < SuperAdmin::ApplicationController
  before_action :fetch_account
  before_action :fetch_config

  def index
    @remote_status = Automations::ProvisioningService.new(@account).remote_status if @config.enabled?
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

  private

  def fetch_account
    @account = Account.find(params[:account_id])
  end

  def fetch_config
    @config = @account.account_automation_config || @account.build_account_automation_config
    @config.save! if @config.new_record?
  end

  # rubocop:disable Rails/I18nLocaleTexts
  def enable!
    result = Automations::ProvisioningService.new(@account).provision!

    if result.success?
      @config.update!(
        enabled: true,
        remote_account_id: result.data.is_a?(Hash) ? result.data['id'] : nil,
        last_provisioned_at: Time.current,
        last_status: 'ok',
        last_error: nil
      )
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'Automations activado para esta cuenta'
    else
      @config.update!(enabled: false, last_status: 'error', last_error: result.error)
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: "No se pudo activar Automations: #{result.error}"
    end
  end

  def disable!
    result = Automations::ProvisioningService.new(@account).deprovision!

    if result.success?
      @config.update!(enabled: false, last_status: 'ok', last_error: nil)
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'Automations desactivado para esta cuenta'
    else
      @config.update!(enabled: false, last_status: 'error', last_error: result.error)
      redirect_to super_admin_account_account_automations_path(@account),
                  alert: "Automations desactivado localmente, pero el servicio remoto falló: #{result.error}"
    end
  end
  # rubocop:enable Rails/I18nLocaleTexts
end
