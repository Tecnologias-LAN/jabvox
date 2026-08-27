# frozen_string_literal: true

require 'administrate/base_dashboard'

class JabvoxBillingConfigDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    unpaid_account_cleanup_days: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    unpaid_account_cleanup_days
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    unpaid_account_cleanup_days
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    unpaid_account_cleanup_days
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(billing_config)
    "Configuración de Billing"
  end
end
