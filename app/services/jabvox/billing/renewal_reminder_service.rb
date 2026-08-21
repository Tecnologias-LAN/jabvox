# frozen_string_literal: true

# Recordatorio de renovación (cobro manual recurrente). Bold no cobra automáticamente:
# cuando el plan de una cuenta está por vencer, se avisa al admin para que renueve con un
# nuevo pago. El pago aprobado ACUMULA vigencia desde la fecha de expiración vigente
# (ver Jabvox::Billing::ProvisioningService#apply_plan_period!).
#
# Pensado para correr a diario (cron). Idempotente por día: no reenvía si ya se avisó hoy.
class Jabvox::Billing::RenewalReminderService
  # Días antes del vencimiento en que se avisa por correo (el pop-up in-app cubre 2 y 1).
  REMINDER_DAYS = [7, 3, 2, 1].freeze

  def call(now: Time.current)
    accounts_due(now).find_each do |account|
      days_left = ((account.jabvox_plan_expires_at - now) / 1.day).ceil
      next unless REMINDER_DAYS.include?(days_left)
      next if already_reminded_today?(account, now)

      send_reminder(account, days_left)
      mark_reminded!(account, now)
    end
  end

  private

  # Cuentas con plan asignado que vence dentro de la ventana máxima de aviso.
  def accounts_due(now)
    Account.where.not(jabvox_plan_id: nil)
           .where(jabvox_plan_expires_at: now..(now + REMINDER_DAYS.max.days))
  end

  def send_reminder(account, days_left)
    admin = account.administrators.first
    return if admin&.email.blank?

    Jabvox::Billing::RenewalMailer.reminder(
      email: admin.email,
      account_name: account.name,
      plan_name: account.jabvox_plan&.name,
      expires_at: account.jabvox_plan_expires_at,
      days_left: days_left
    ).deliver_later
  end

  def already_reminded_today?(account, now)
    account.internal_attributes['renewal_reminder_sent_on'] == now.to_date.iso8601
  end

  # Marca el aviso de hoy con un row-lock + reload dentro de la transacción, para no pisar
  # otros cambios concurrentes sobre internal_attributes (jsonb compartido).
  def mark_reminded!(account, now)
    account.with_lock do
      attrs = account.internal_attributes.to_h.merge('renewal_reminder_sent_on' => now.to_date.iso8601)
      account.update_column(:internal_attributes, attrs) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
