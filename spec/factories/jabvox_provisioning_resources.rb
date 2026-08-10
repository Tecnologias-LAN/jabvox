# frozen_string_literal: true

# Factories mínimas para los recursos Jabvox con cuota por cuenta (usados en los specs
# de límites de aprovisionamiento).
FactoryBot.define do
  factory :jabvox_analytics_dashboard do
    account
    sequence(:name_jabvox) { |n| "Dashboard #{n}" }
  end

  factory :jabvox_ai_chat_document do
    account
    sequence(:name_jabvox) { |n| "Doc IA #{n}" }
    sequence(:s3_key_jabvox) { |n| "ai-chat/doc-#{n}.pdf" }
  end

  factory :jabvox_response_bot_document do
    account
    sequence(:name_jabvox) { |n| "Doc bot #{n}" }
    sequence(:s3_key_jabvox) { |n| "response-bot/doc-#{n}.pdf" }
  end
end
