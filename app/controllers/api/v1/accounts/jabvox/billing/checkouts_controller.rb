# frozen_string_literal: true

# Inicio del flujo de pago DENTRO de la app (sin web de cobro externa). El admin de la
# cuenta elige un plan y este endpoint:
#   1) crea la transacción payment_pending LIGADA a la cuenta actual,
#   2) pide a la pasarela activa (Bold) el link de pago,
#   3) devuelve la checkout_url a la que redirigir el navegador.
#
# La cuenta se ACTIVA luego por el webhook firmado de la pasarela (nunca aquí): así no se
# puede saltar ni falsificar el pago. Sirve tanto para el primer pago (cuenta
# payment_pending recién registrada) como para la RENOVACIÓN (cuenta suspended por plan
# vencido): en ambos casos la cuenta no está activa y elige un plan para pagar.
#
# POST /api/v1/accounts/:account_id/jabvox/billing/checkout
#   { "plan_id": 3 }  ->  { "checkout_url": "https://checkout.bold.co/...", "idempotency_key": "..." }
#
# No gateado por módulo Jabvox (cualquier admin puede pagar/renovar); protegido por la
# autenticación de cuenta heredada del BaseController.
class Api::V1::Accounts::Jabvox::Billing::CheckoutsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature :none

  before_action :ensure_administrator
  before_action :fetch_plan
  before_action :fetch_gateway

  def create
    render json: perform_checkout, status: :created
  rescue Jabvox::Billing::Gateways::GatewayError => e
    Rails.logger.error("[JabvoxCheckout] #{e.message}")
    render json: { error: 'gateway_error' }, status: :bad_gateway
  end

  private

  # Debe funcionar con la cuenta inactiva: es el endpoint que inicia el pago para
  # desbloquearla. Sin esto, una cuenta payment_pending/suspended nunca podría pagar.
  def allow_inactive_account?
    true
  end

  def fetch_plan
    @plan = JabvoxPlan.sellable.find_by(id: params[:plan_id])
    render json: { error: 'Plan no disponible' }, status: :unprocessable_entity if @plan.nil?
  end

  def fetch_gateway
    @gateway = Jabvox::Billing::Gateways::Base.for_active
    render json: { error: 'no_active_gateway' }, status: :unprocessable_entity if @gateway.nil?
  end

  def ensure_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'Solo un administrador puede iniciar el pago' }, status: :forbidden
  end

  # Crea la transacción pendiente ligada a la cuenta actual, pide la URL a la pasarela y
  # devuelve el payload. idempotency_key única = referencia del pago.
  def perform_checkout
    txn = JabvoxProvisioningTransaction.create!(
      account: Current.account,
      jabvox_plan: @plan,
      buyer_email: buyer_email,
      gateway: @gateway.provider,
      idempotency_key: SecureRandom.uuid,
      amount_cents: @plan.price_cents,
      currency: @plan.currency,
      status: :payment_pending
    )

    checkout = @gateway.create_checkout(
      amount_cents: @plan.price_cents,
      currency: @plan.currency,
      reference: txn.idempotency_key,
      metadata: {
        account_id: Current.account.id, plan_id: @plan.id,
        idempotency_key: txn.idempotency_key, payer_email: txn.buyer_email,
        callback_url: success_callback_url
      }
    )
    txn.update!(gateway_reference: checkout[:reference])
    { checkout_url: checkout[:checkout_url], idempotency_key: txn.idempotency_key }
  end

  def buyer_email
    Current.account.administrators.first&.email || Current.user&.email
  end

  # A dónde vuelve el navegador tras pagar en la pasarela. La activación ya la hizo el
  # webhook; esta pantalla solo refresca el estado de la cuenta.
  def success_callback_url
    base = ENV.fetch('FRONTEND_URL', 'https://app.jabvox.com').delete_suffix('/')
    "#{base}/app/accounts/#{Current.account.id}/dashboard"
  end
end
