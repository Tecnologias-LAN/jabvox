# Encola en la cola aislada jabvox_automations el reintento de una operación
# remota que falló por red, para no bloquear el request ni dejar a Jabvox y
# Automations discrepando por un corte pasajero.
module SuperAdmin::AccountAutomationsRetry
  extend ActiveSupport::Concern

  private

  # Reintenta solo la desactivación remota fallida por red; el estado local ya se
  # aplicó, esto garantiza que el enabled:false acabe llegando al remoto.
  def schedule_disable_retry(result)
    return if result.success? || !result.retryable?

    Jabvox::Automations::ProvisionJob.perform_later(@account.id, 'update_module',
                                                    max_flows: @config.max_flows, enabled: false)
  end

  def enqueue_background_retry(operation, opts = {})
    Jabvox::Automations::ProvisionJob.perform_later(@account.id, operation, opts)
    redirect_to super_admin_account_account_automations_path(@account),
                notice: 'La plataforma de automatizaciones no respondió a tiempo. La operación se está ' \
                        'reintentando en segundo plano; recarga en unos segundos para ver el estado final.'
  end
end
