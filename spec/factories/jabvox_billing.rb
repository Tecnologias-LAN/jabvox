# frozen_string_literal: true

FactoryBot.define do
  factory :jabvox_plan do
    sequence(:name) { |n| "Plan #{n}" }
    sequence(:slug) { |n| "plan-#{n}" }
    price_cents { 5_000_00 }
    currency { 'COP' }
    duration_days { 30 }
    status { :active }
    modules { %w[tickets kanban] }
    chatwoot_features { [] }
    limits { { 'agents' => 5, 'forms' => 1 } }
  end

  factory :jabvox_payment_gateway_config do
    provider { 'bold' }
    active { false }
    public_token { 'pub_test_123' }
    checkout_base_url { 'https://checkout.bold.co' }
  end

  factory :jabvox_provisioning_transaction do
    association :jabvox_plan
    buyer_email { 'comprador@empresa.com' }
    gateway { 'bold' }
    sequence(:idempotency_key) { |n| "idem-#{n}" }
    amount_cents { 5_000_00 }
    currency { 'COP' }
    status { :payment_pending }
  end
end
