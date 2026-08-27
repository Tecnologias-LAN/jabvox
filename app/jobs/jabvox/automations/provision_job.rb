# Reintenta en background las operaciones HTTP salientes de Automations
# (aprovisionar / actualizar módulo / desaprovisionar) que fallaron por red.
# Cola aislada (jabvox_automations) con backoff, para no bloquear el request del
# super admin ni dejar a Jabvox y Automations discrepando por un corte pasajero.
# Idempotente: las operaciones son upsert/estado absoluto. El resultado queda en
# last_status/last_error, que la UI del super admin lee al recargar.
class Jabvox::Automations::ProvisionJob < ApplicationJob
  queue_as :jabvox_automations

  # Los services rescatan la excepción de Faraday y devuelven un Result; sin esta
  # excepción propia el retry de Sidekiq nunca se dispararía.
  TransientError = Class.new(StandardError)

  retry_on TransientError, wait: :polynomially_longer, attempts: 5

  OPERATIONS = %w[provision update_module deprovision].freeze

  def perform(account_id, operation, opts = {})
    return Rails.logger.warn("[Automations::Provision] operación desconocida=#{operation}") unless OPERATIONS.include?(operation.to_s)

    account = Account.find_by(id: account_id)
    return unless account

    config = account.account_automation_config
    return unless config

    result = public_send("run_#{operation}", account, config, opts.symbolize_keys)
    log_result(account, operation, result)
    # Relanza solo si el fallo es de red: dispara el retry con backoff. Un error de
    # negocio (401/404/config) no se reintenta, solo queda en last_status.
    raise TransientError, "#{operation} account=#{account.id}: #{result.error}" if result && !result.success? && result.retryable?
  end

  private

  def run_provision(account, config, _opts)
    Automations::AccountProvisioner.new(account, config).call
  end

  def run_update_module(account, config, opts)
    result = Automations::ProvisioningService.new(account)
                                             .update_module!(max_flows: opts[:max_flows], enabled: opts[:enabled])
    persist(config, result)
    result
  end

  def run_deprovision(account, config, _opts)
    result = Automations::ProvisioningService.new(account).deprovision!
    persist(config, result)
    result
  end

  def persist(config, result)
    config.update(last_status: result.success? ? 'ok' : 'error',
                  last_error: result.success? ? nil : result.error)
    Automations::StateService.new(config.account).recalculate!(remote_result: result)
  end

  def log_result(account, operation, result)
    return if result.nil?

    if result.success?
      Rails.logger.info("[Automations::Provision] account=#{account.id} op=#{operation} ok")
    else
      retryable = result.retryable? ? ' (se reintentará)' : ''
      Rails.logger.warn("[Automations::Provision] account=#{account.id} op=#{operation} error=#{result.error}#{retryable}")
    end
  end
end
