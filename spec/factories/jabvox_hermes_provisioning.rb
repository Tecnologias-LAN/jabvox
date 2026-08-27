# frozen_string_literal: true

FactoryBot.define do
  factory :jabvox_context_forge_handoff do
    association :account
    status { 'pending' }

    trait :ready do
      status { 'ready' }
      contextforge_base_url { 'https://cf.example/api' }
      virtual_server_id { 'vs-test' }
      team_id { 'team-test' }
      scoped_token { 'scoped-token-test' }
      mcp_servers { [{ 'kind' => 'jabvox_core', 'ok' => true }] }
      provisioned_at { Time.current }
    end
  end

  factory :jabvox_provisioning_chat_message do
    association :account
    association :user
    role { 'user' }
    content { 'crea un mcp de analytics' }
    metadata { {} }
  end

  factory :jabvox_ai_chat_model do
    association :account
    sequence(:name_jabvox) { |n| "Modelo #{n}" }
    provider_jabvox { 'openai' }
    model_jabvox { 'gpt-4o-mini' }
    source_jabvox { 'local' }
  end
end
