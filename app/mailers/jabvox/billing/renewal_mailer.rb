# frozen_string_literal: true

# Aviso de renovación: el plan de la cuenta está por vencer. El correo invita a renovar
# (cobro manual: Bold no cobra automáticamente). No incluye datos sensibles.
class Jabvox::Billing::RenewalMailer < ApplicationMailer
  layout false

  def reminder(email:, account_name:, plan_name:, expires_at:, days_left:)
    @account_name = account_name
    @plan_name = plan_name
    @expires_at = expires_at
    @days_left = days_left
    @app_url = ENV.fetch('FRONTEND_URL', 'https://app.jabvox.com')
    mail(to: email, subject: I18n.t('jabvox.billing.renewal_mailer.reminder.subject', days: days_left))
  end
end
