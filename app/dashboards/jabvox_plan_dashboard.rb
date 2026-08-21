require 'administrate/base_dashboard'

# Panel Super Admin del catálogo de planes (editable). En `limits` se pueden guardar
# cuotas y precios extra por recurso:
#   { "agents": { "included": 5, "unit_price_cents": 1000 },
#     "storage_gb": { "included": 10, "unit_price_cents": 500 } }
class JabvoxPlanDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    slug: Field::String,
    price_cents: Field::Number,
    currency: Field::String,
    duration_days: Field::Number,
    billing_period: Field::Select.with_options(collection: JabvoxPlan.billing_periods.keys),
    status: Field::Select.with_options(collection: JabvoxPlan.statuses.keys),
    sort_order: Field::Number,
    whatsapp_number: Field::String,
    modules: Field::String.with_options(searchable: false),
    chatwoot_features: Field::String.with_options(searchable: false),
    limits: Field::String.with_options(searchable: false),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    price_cents
    duration_days
    billing_period
    status
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    slug
    price_cents
    currency
    duration_days
    billing_period
    status
    sort_order
    whatsapp_number
    modules
    chatwoot_features
    limits
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    slug
    price_cents
    currency
    duration_days
    billing_period
    status
    sort_order
    whatsapp_number
    modules
    chatwoot_features
    limits
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(plan)
    "#{plan.name} (#{plan.status})"
  end
end
