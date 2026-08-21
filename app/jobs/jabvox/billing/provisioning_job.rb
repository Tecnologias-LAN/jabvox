# frozen_string_literal: true

# Aprovisiona una cuenta a partir de una transacción de pago aprobada, con reintentos
# automáticos controlados. La idempotencia la garantiza ProvisioningService (no habilita
# tiempo dos veces aunque el job corra varias veces).
#
# Reintentos: hasta MAX_PROVISION_ATTEMPTS con backoff exponencial. Al agotarlos, deja la
# transacción en provisioning_failed (visible en el panel para acción manual) SIN que el
# usuario pierda el pago.
class Jabvox::Billing::ProvisioningJob < ApplicationJob
  queue_as :jabvox_payments

  retry_on Jabvox::Billing::ProvisioningError,
           wait: :polynomially_longer,
           attempts: JabvoxProvisioningTransaction::MAX_PROVISION_ATTEMPTS do |job, error|
    # Callback tras agotar los reintentos: marcar fallo y notificar al panel.
    tx = JabvoxProvisioningTransaction.find_by(id: job.arguments.first)
    tx&.mark_provisioning_failed!(error.message)
    Rails.logger.error("[BillingProvisioning] tx=#{job.arguments.first} agotó reintentos: #{error.message}")
  end

  def perform(transaction_id)
    tx = JabvoxProvisioningTransaction.find(transaction_id)
    return if tx.provisioned? # idempotencia: ya está listo, nada que hacer

    result = Jabvox::Billing::ProvisioningService.new(tx).call

    # Cuenta nueva -> enviar correo con link seguro para establecer contraseña.
    send_credentials_email(tx, result)
  end

  private

  def send_credentials_email(txn, result)
    return unless result[:created_user] && result[:set_password_url].present?

    Jabvox::Billing::CredentialsMailer.set_password(
      email: txn.buyer_email,
      account_name: result[:account]&.name,
      set_password_url: result[:set_password_url]
    ).deliver_later
  end
end
