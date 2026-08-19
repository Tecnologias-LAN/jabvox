# frozen_string_literal: true

# Aprovisiona Hermes/ContextForge para una cuenta en segundo plano (crea recursos remotos).
# Idempotente: reintentar sobre la misma cuenta reconcilia, no duplica.
class ContextForge::AccountProvisionJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.nil?

    result = ContextForge::AccountProvisioner.new(account).call
    Rails.logger.error("[ContextForge] provision job failed account=#{account_id}: #{result.error}") unless result.success?
    result
  end
end
