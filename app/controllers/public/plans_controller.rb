# frozen_string_literal: true

# Endpoint público (sin autenticación) para listar los planes disponibles. Usado por la
# landing page de cobro (jabvox.com) y por la pantalla de registro para mostrar las opciones
# de pago antes del login.
#
# GET /public/plans
#   Respuesta:
#   [
#     {
#       "id": 1,
#       "name": "Plan Básico",
#       "slug": "plan-basico",
#       "price_cents": 99000,
#       "currency": "COP",
#       "price_formatted": "$990.00",
#       "billing_period": "monthly",
#       "duration_days": 30,
#       "modules": ["tickets", "kanban"],
#       "features": ["crm"],
#       "limits": { "inboxes": 5, "agents": 10, "storage_gb": 15,
#                   "agents_unit_price_cents": 1000 }
#     }
#   ]
#
# GET /public/plans/:slug
#   Respuesta: plan individual con la misma estructura
class Public::PlansController < ActionController::API
  def index
    plans = JabvoxPlan.sellable.ordered
    render json: plans.map { |p| serialize_plan(p) }
  end

  def show
    plan = JabvoxPlan.sellable.find_by!(slug: params[:id])
    render json: serialize_plan(plan)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Plan no encontrado' }, status: :not_found
  end

  private

  def serialize_plan(plan)
    {
      id: plan.id,
      name: plan.name,
      slug: plan.slug,
      price_cents: plan.price_cents,
      currency: plan.currency,
      price_formatted: format_price(plan.price, plan.currency),
      billing_period: plan.billing_period,
      duration_days: plan.duration_days,
      modules: plan.modules || [],
      features: plan.chatwoot_features || [],
      limits: plan.provisioning_limits,
      whatsapp_number: plan.whatsapp_number,
      sort_order: plan.sort_order
    }
  end

  def format_price(price, currency)
    symbol = currency == 'COP' ? '$' : currency
    "#{symbol}#{format('%.2f', price)}"
  end
end
