# frozen_string_literal: true

FactoryBot.define do
  factory :jabvox_drive_storage_account do
    account
    used_bytes { 0 }
    reserved_bytes { 0 }
    overflow_bytes { 0 }
  end

  factory :jabvox_drive_folder do
    account
    sequence(:name) { |n| "Carpeta #{n}" }
    system_folder { false }
  end

  factory :jabvox_drive_file do
    account
    sequence(:filename) { |n| "archivo-#{n}.txt" }
    content_type { 'text/plain' }
    bucket { 'primary' }
    sequence(:object_key) { |n| "acct-0/archivo-#{n}.txt" }
    byte_size { 100 }
    status { :available }

    # object_key debe empezar con el prefijo real de la cuenta.
    after(:build) do |file|
      file.object_key = "acct-#{file.account_id}/#{file.filename}" if file.account_id
    end
  end

  factory :jabvox_drive_audit_log do
    account
    action { 'upload' }
    result { 'success' }
    metadata { {} }
  end

  factory :jabvox_drive_pending_operation do
    account
    kind { 'ingest_media' }
    sequence(:idempotency_key) { |n| "op-key-#{n}" }
    status { :pending }
    payload { {} }
  end
end
