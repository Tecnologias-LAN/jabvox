# frozen_string_literal: true

module Jabvox::AccountBillingEntitlements
  extend ActiveSupport::Concern

  BILLABLE_RESOURCE_KEYS = JabvoxPlan::BILLABLE_RESOURCE_KEYS

  def billable_limits
    (limits || {}).to_h.stringify_keys
  end

  def base_limit_for(resource)
    resource = resource.to_s
    value = billable_limits["#{resource}_included"]
    value = jabvox_plan&.included_limit_for(resource) if value.blank?
    value = billable_limits[resource] if value.blank?
    numeric_limit(value)
  end

  def extra_limit_for(resource)
    numeric_limit(billable_limits["#{resource}_extra"])
  end

  def effective_limit_for(resource)
    resource = resource.to_s
    return base_limit_for(resource).to_i + extra_limit_for(resource).to_i if billable_breakdown_configured?(resource)

    configured = numeric_limit(billable_limits[resource])
    return configured if configured.positive?

    base_limit_for(resource).to_i + extra_limit_for(resource).to_i
  end

  def unit_price_cents_for(resource)
    resource = resource.to_s
    price = numeric_limit(billable_limits["#{resource}_unit_price_cents"])
    price = jabvox_plan&.unit_price_cents_for(resource).to_i if price.zero?
    price
  end

  def billable_extra_cents_for(resource)
    extra_limit_for(resource).to_i * unit_price_cents_for(resource).to_i
  end

  def billable_extra_cents
    BILLABLE_RESOURCE_KEYS.sum { |key| billable_extra_cents_for(key) }
  end

  def billable_base_cents
    jabvox_plan&.price_cents.to_i
  end

  def billable_total_cents
    billable_base_cents + billable_extra_cents
  end

  def billable_limits_summary
    BILLABLE_RESOURCE_KEYS.index_with do |resource|
      {
        included: base_limit_for(resource),
        extra: extra_limit_for(resource),
        limit: effective_limit_for(resource),
        used: usage_count_for(resource),
        unit_price_cents: unit_price_cents_for(resource),
        extra_price_cents: billable_extra_cents_for(resource)
      }
    end
  end

  def storage_quota_bytes
    effective_limit_for(:storage_gb).to_i.gigabytes
  end

  def storage_over_quota?(additional_bytes = 0)
    quota = storage_quota_bytes
    return false if quota <= 0

    Jabvox::StorageUsageService.new(self).total_bytes + additional_bytes.to_i > quota
  end

  private

  def usage_count_for(resource)
    case resource.to_s
    when 'agents'
      account_users.count
    when 'inboxes'
      inboxes.count
    when 'forms'
      jabvox_forms.count
    when 'advanced_flows'
      jabvox_flows.count
    when 'automation_rules'
      automation_rules.count
    when 'analytics_dashboards'
      jabvox_analytics_dashboards.count
    when 'ai_documents'
      jabvox_ai_chat_documents.count + jabvox_response_bot_documents.count
    when 'email_templates'
      jabvox_email_templates.count
    when 'storage_gb'
      Jabvox::StorageUsageService.new(self).total_gb.round(2)
    else
      0
    end
  end

  def numeric_limit(value)
    return 0 if value.blank?
    return value.to_i if value.is_a?(Numeric)
    return value.to_i if value.to_s.match?(/\A\d+\z/)

    0
  end

  def billable_breakdown_configured?(resource)
    billable_limits.key?("#{resource}_included") || billable_limits.key?("#{resource}_extra")
  end
end
