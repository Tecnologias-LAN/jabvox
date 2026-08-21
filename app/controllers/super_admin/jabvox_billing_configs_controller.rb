# frozen_string_literal: true

# Configuración de billing: cuántos días esperar antes de eliminar cuentas sin pago.
class SuperAdmin::JabvoxBillingConfigsController < SuperAdmin::ApplicationController
  def edit
    @config = JabvoxBillingConfig.instance
  end

  def update
    @config = JabvoxBillingConfig.instance
    if @config.update(config_params)
      redirect_to edit_super_admin_jabvox_billing_config_path, notice: 'Configuración actualizada'
    else
      render :edit
    end
  end

  private

  def config_params
    params.require(:jabvox_billing_config).permit(:unpaid_account_cleanup_days)
  end
end
