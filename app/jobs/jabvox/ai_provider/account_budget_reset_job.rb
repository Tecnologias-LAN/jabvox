# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module AiProvider
    # Restablece el saldo del plan de UNA cuenta (encolado por el dispatcher mensual).
    # Reintenta errores transitorios del proveedor; la idempotencia por periodo del
    # BalanceService evita que un reintento restablezca dos veces.
    class AccountBudgetResetJob < ApplicationJob
      queue_as :jabvox_payments

      retry_on StandardError, wait: :polynomially_longer, attempts: 5

      def perform(account_id)
        account = Account.find_by(id: account_id)
        return if account.nil? || account.jabvox_plan_id.nil?

        result = Jabvox::AiProvider::BalanceService.new(account).reset_monthly!
        return if result.success?

        # Falla → deja que retry_on reintente (el error se propaga).
        raise "reset mensual falló para cuenta #{account_id}: #{result.error}"
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
