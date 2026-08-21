json.settings resource.settings
json.created_at resource.created_at
if resource.custom_attributes.present?
  json.custom_attributes do
    json.plan_name resource.custom_attributes['plan_name']
    json.subscribed_quantity resource.custom_attributes['subscribed_quantity']
    json.subscription_status resource.custom_attributes['subscription_status']
    json.subscription_ends_on resource.custom_attributes['subscription_ends_on']
    json.billing_currency resource.billing_currency if resource.respond_to?(:billing_currency) && Enterprise::Billing::Currencies.enabled?
    json.website resource.custom_attributes['website'] if resource.custom_attributes['website'].present?
    json.industry resource.custom_attributes['industry'] if resource.custom_attributes['industry'].present?
    json.company_size resource.custom_attributes['company_size'] if resource.custom_attributes['company_size'].present?
    json.timezone resource.custom_attributes['timezone'] if resource.custom_attributes['timezone'].present?
    json.logo resource.custom_attributes['logo'] if resource.custom_attributes['logo'].present?
    json.referral_source resource.custom_attributes['referral_source'] if resource.custom_attributes['referral_source'].present?
    json.brand_info resource.custom_attributes['brand_info'] if resource.custom_attributes['brand_info'].present?
    json.onboarding_step resource.onboarding_step if resource.onboarding_step.present?
    if resource.custom_attributes['help_center_generation_id'].present?
      json.help_center_generation_id resource.custom_attributes['help_center_generation_id']
    end
    json.marked_for_deletion_at resource.custom_attributes['marked_for_deletion_at'] if resource.custom_attributes['marked_for_deletion_at'].present?
    if resource.custom_attributes['marked_for_deletion_reason'].present?
      json.marked_for_deletion_reason resource.custom_attributes['marked_for_deletion_reason']
    end
  end
end
json.domain @account.domain
json.features @account.enabled_features
json.id @account.id
json.locale @account.locale
json.name @account.name
json.support_email @account.support_email
json.status @account.status
json.cache_keys @account.cache_keys
json.jabvox_billing do
  json.plan do
    json.id @account.jabvox_plan_id
    json.name @account.jabvox_plan&.name
    json.expires_at @account.jabvox_plan_expires_at
  end
  json.limits @account.billable_limits_summary
  json.storage Jabvox::StorageUsageService.new(@account).call
  json.base_price_cents @account.billable_base_cents
  json.extra_price_cents @account.billable_extra_cents
  json.total_price_cents @account.billable_total_cents
  json.currency @account.jabvox_plan&.currency || 'COP'
end
