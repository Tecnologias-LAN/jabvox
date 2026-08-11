# frozen_string_literal: true

# Inicio del flujo de pago desde la app. El admin de la cuenta elige un plan y este
# endpoint devuelve un token FIRMADO (con expiración) + la URL de la web de cobro a la
# que redirigir. El account_id NO viaja en claro: va dentro del token.
#
# POST /api/v1/accounts/:account_id/jabvox/billing/checkout
#   { "plan_id": 3 }  ->  { "token": "...", "checkout_url": "https://.../checkout?token=..." }
#
# No gateado por módulo Jabvox (cualquier admin puede pagar/renovar); protegido por la
# autenticación de cuenta heredada del BaseController.
class Api::V1::Accounts::Jabvox::Billing::CheckoutsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature :none

  before_action :ensure_administrator
  before_action :fetch_plan

  def create
    token = Jabvox::Billing::CheckoutTokenService.encode(
      account_id: Current.account.id, plan_id: @plan.id
    )
    render json: { token: token, checkout_url: build_checkout_url(token) }, status: :created
  end

  private

  def fetch_plan
    @plan = JabvoxPlan.sellable.find_by(id: params[:plan_id])
    render json: { error: 'Plan no disponible' }, status: :unprocessable_entity if @plan.nil?
  end

  def ensure_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'Solo un administrador puede iniciar el pago' }, status: :forbidden
  end

  # URL de la web de cobro. Configurable por ENV para no fijar el dominio en código.
  def build_checkout_url(token)
    base = ENV.fetch('JABVOX_WEB_CHECKOUT_URL', 'https://jabvox.com/checkout').delete_suffix('/')
    "#{base}?token=#{token}"
  end
end
