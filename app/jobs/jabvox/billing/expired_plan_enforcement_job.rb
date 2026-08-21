# frozen_string_literal: true

module Jabvox
  module Billing
    class ExpiredPlanEnforcementJob < ApplicationJob
      queue_as :jabvox_payments

      def perform
        expired_accounts = Account.active
                                  .where.not(jabvox_plan_id: nil)
                                  .where('jabvox_plan_expires_at < ?', Time.current)

        expired_accounts.find_each do |account|
          Rails.logger.info("[ExpiredPlanEnforcement] Suspendiendo cuenta #{account.id} por expiración de plan")
          account.update!(status: :suspended)
        end
      end
    end
  end
end
