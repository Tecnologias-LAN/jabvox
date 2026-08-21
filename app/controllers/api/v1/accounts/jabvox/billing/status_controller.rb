# frozen_string_literal: true

# Estado de pago de la cuenta actual (autenticado). El frontend lo consulta al cargar
# para decidir si mostrar el modal de bloqueo (payment_pending / suspended) o dejar pasar
# (active). Solo lectura; la activación real ocurre por el webhook firmado de la pasarela.
#
# GET /api/v1/accounts/:account_id/jabvox/billing/status
class Api::V1::Accounts::Jabvox::Billing::StatusController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature :none

  def show
    account = Current.account
    render json: {
      status: account.status,
      requires_payment: !account.active?,
      plan_id: account.jabvox_plan_id,
      plan_name: account.jabvox_plan&.name,
      plan_expires_at: account.jabvox_plan_expires_at,
      last_transaction: last_transaction_summary(account)
    }
  end

  private

  # Debe funcionar con la cuenta inactiva: es justo lo que consulta el modal de bloqueo.
  def allow_inactive_account?
    true
  end

  def last_transaction_summary(account)
    txn = account.jabvox_provisioning_transactions.order(created_at: :desc).first
    return nil if txn.nil?

    {
      id: txn.id, status: txn.status, gateway: txn.gateway,
      amount_cents: txn.amount_cents, currency: txn.currency,
      created_at: txn.created_at, payment_approved_at: txn.payment_approved_at
    }
  end
end
