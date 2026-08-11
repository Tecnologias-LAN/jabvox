# frozen_string_literal: true

# Corre a diario (cron) y envía recordatorios de renovación a las cuentas cuyo plan está
# por vencer. Ver Jabvox::Billing::RenewalReminderService.
class Jabvox::Billing::RenewalReminderJob < ApplicationJob
  queue_as :low

  def perform
    Jabvox::Billing::RenewalReminderService.new.call
  end
end
