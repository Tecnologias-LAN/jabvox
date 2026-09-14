# frozen_string_literal: true

FactoryBot.define do
  factory :jabvox_affiliate do
    account
    sequence(:name) { |n| "Afiliado #{n}" }
    sequence(:portal_slug) { |n| "afiliado-#{n}" }
    active { true }
    # account_code y auth_token los genera el propio modelo en before_validation.
  end
end
