# frozen_string_literal: true

# Envía recordatorios de renovación a cuentas activas cuyo plan expire en 7, 3 o 1 día.
# Corre diariamente. Es idempotente por día (no envía múltiples recordatorios el mismo día).
class Jabvox::Billing::RenewalReminderJob < ApplicationJob
  queue_as :jabvox_payments

  def perform
    Jabvox::Billing::RenewalReminderService.new.call
  end
end
