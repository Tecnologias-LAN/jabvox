require 'administrate/field/base'

class AccountLimitsField < Administrate::Field::Base
  DEFAULT_KEYS = %i[
    agents
    inboxes
    forms
    advanced_flows
    automation_rules
    analytics_dashboards
    ai_documents
    email_templates
    storage_gb
    captain_responses
    captain_documents
    emails
  ].freeze

  def to_s
    defaults = DEFAULT_KEYS.index_with { nil }
    overrides = (data.presence || {}).to_h.symbolize_keys.compact

    defaults.merge(overrides).to_json
  end

  def billable_summary
    return {} unless resource.respond_to?(:billable_limits_summary)

    resource.billable_limits_summary
  end

  def extra_price_cents
    return 0 unless resource.respond_to?(:billable_extra_cents)

    resource.billable_extra_cents
  end
end
