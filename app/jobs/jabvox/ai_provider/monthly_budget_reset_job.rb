# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module AiProvider
    # Worker mensual (dispatcher): recorre las cuentas con plan de IA activo y encola un job
    # POR CUENTA para restablecer el saldo del plan. Fan-out para escalar y aislar fallos: una
    # cuenta que falle no detiene al resto. Idempotente por periodo (no restablece dos veces).
    class MonthlyBudgetResetJob < ApplicationJob
      queue_as :jabvox_payments

      def perform
        return unless JabvoxAiProviderConfig.instance.enabled_jabvox

        # Solo cuentas con plan que otorga saldo de IA (> 0).
        plan_ids = JabvoxPlan.where('ai_budget_cents_jabvox > 0').pluck(:id)
        return if plan_ids.empty?

        Account.where(jabvox_plan_id: plan_ids).find_each do |account|
          Jabvox::AiProvider::AccountBudgetResetJob.perform_later(account.id)
        end
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
