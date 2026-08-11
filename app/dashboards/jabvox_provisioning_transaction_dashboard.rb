require 'administrate/base_dashboard'

# Panel Super Admin: visual de estados entre pago y aprovisionamiento. Cada transacción
# muestra su estado, motivo, intentos y tiempos. Las fallidas se pueden reintentar
# manualmente desde el show. Es de solo lectura (no se crean/editan a mano).
class JabvoxProvisioningTransactionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    jabvox_plan: Field::BelongsTo,
    buyer_email: Field::String,
    gateway: Field::String,
    gateway_reference: Field::String,
    idempotency_key: Field::String,
    amount_cents: Field::Number,
    currency: Field::String,
    status: Field::Select.with_options(collection: JabvoxProvisioningTransaction.statuses.keys),
    status_reason: Field::Text,
    attempts: Field::Number,
    payment_approved_at: Field::DateTime,
    provisioned_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    buyer_email
    gateway
    status
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    jabvox_plan
    buyer_email
    gateway
    gateway_reference
    idempotency_key
    amount_cents
    currency
    status
    status_reason
    attempts
    payment_approved_at
    provisioned_at
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(txn)
    "##{txn.id} · #{txn.buyer_email} · #{txn.status}"
  end
end
