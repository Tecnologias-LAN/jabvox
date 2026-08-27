# frozen_string_literal: true

# Historial de pagos de la cuenta actual (autenticado). Lista las transacciones con su
# medio de pago, monto, moneda, estado y fechas, para mostrarlas en Ajustes → Facturación.
# Solo lectura; nunca expone datos sensibles (el medio de pago viene enmascarado).
#
# GET /api/v1/accounts/:account_id/jabvox/billing/payments
class Api::V1::Accounts::Jabvox::Billing::PaymentsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature :none

  before_action :ensure_administrator

  def index
    txns = Current.account.jabvox_provisioning_transactions
                  .includes(:jabvox_plan)
                  .order(created_at: :desc)
                  .limit(100)

    render json: { payments: txns.map { |t| serialize(t) } }
  end

  private

  # Funciona con la cuenta inactiva: el cliente puede ver su historial mientras paga.
  def allow_inactive_account?
    true
  end

  def ensure_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'solo_administradores' }, status: :forbidden
  end

  def serialize(txn)
    {
      id: txn.id,
      plan_name: txn.plan_name,
      amount_cents: txn.amount_cents,
      currency: txn.currency,
      payment_label: txn.payment_label,
      payment_method: txn.payment_method,
      sandbox: txn.sandbox?,
      created_at: txn.created_at,
      payment_approved_at: txn.payment_approved_at
    }
  end
end
