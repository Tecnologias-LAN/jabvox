# frozen_string_literal: true

# Estado de pago de la cuenta actual (autenticado). El frontend lo consulta al cargar y al
# volver del checkout para decidir si mostrar el modal de bloqueo (payment_pending /
# suspended) o dejar pasar (active).
#
# Además, al consultar el estado se VERIFICA ACTIVAMENTE contra la pasarela el último pago
# pendiente: si la pasarela confirma que se aprobó (aunque el webhook no haya llegado), se
# activa la cuenta en el momento. Así el usuario no queda atrapado tras pagar.
#
# GET /api/v1/accounts/:account_id/jabvox/billing/status
class Api::V1::Accounts::Jabvox::Billing::StatusController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature :none

  def show
    account = Current.account
    verify_pending_payment(account) unless account.active?
    account.reload

    days_left = account.days_until_expiration
    render json: {
      status: account.status,
      requires_payment: !account.active?,
      plan_id: account.jabvox_plan_id,
      plan_name: account.jabvox_plan&.name,
      plan_expires_at: account.jabvox_plan_expires_at,
      days_until_expiration: days_left,
      # El frontend muestra el pop-up de renovación (cerrable) cuando faltan <= 2 días y
      # la cuenta sigue activa.
      expiring_soon: account.active? && days_left.present? && days_left >= 0 && days_left <= 2,
      last_transaction: last_transaction_summary(account)
    }
  end

  private

  # Debe funcionar con la cuenta inactiva: es justo lo que consulta el modal de bloqueo.
  def allow_inactive_account?
    true
  end

  # Red de seguridad: si hay un pago pendiente, le preguntamos a la pasarela si ya se
  # aprobó y activamos la cuenta si es así (por si el webhook no llegó).
  def verify_pending_payment(account)
    txn = account.jabvox_provisioning_transactions
                 .where(status: :payment_pending)
                 .order(created_at: :desc).first
    return if txn.nil?

    Jabvox::Billing::PaymentVerifier.new(txn).call
  rescue StandardError => e
    Rails.logger.warn("[BillingStatus] verificación de pago falló: #{e.message}")
  end

  def last_transaction_summary(account)
    txn = account.jabvox_provisioning_transactions.order(created_at: :desc).first
    return nil if txn.nil?

    {
      id: txn.id, status: txn.status, gateway: txn.gateway,
      amount_cents: txn.amount_cents, currency: txn.currency,
      payment_method: txn.payment_method,
      created_at: txn.created_at, payment_approved_at: txn.payment_approved_at
    }
  end
end
