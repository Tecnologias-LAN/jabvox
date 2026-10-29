# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    transient do
      skip_confirmation { true }
      role { 'agent' }
      auto_offline { true }
      account { nil }
      inviter { nil }
    end

    provider { 'email' }
    uid { SecureRandom.uuid }
    name { Faker::Name.name }
    display_name { Faker::Name.first_name }
    # Email SIEMPRE válido e independiente del nombre: con locale :es (default de la
    # app) Faker genera nombres con acentos/ñ (p. ej. "José") que, concatenados, dan
    # un email no-ASCII inválido para Devise.email_regexp. Usamos solo ASCII.
    email { "user-#{SecureRandom.hex(8)}@example.com" }
    password { 'Password1!' }

    after(:build) do |user, evaluator|
      user.skip_confirmation! if evaluator.skip_confirmation
      if evaluator.account
        create(:account_user, user: user, account: evaluator.account, role: evaluator.role, inviter: evaluator.inviter,
                              auto_offline: evaluator.auto_offline)
      end
    end

    trait :with_avatar do
      avatar { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }
    end

    trait :administrator do
      role { 'administrator' }
    end
  end
end
