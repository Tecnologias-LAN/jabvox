# frozen_string_literal: true

FactoryBot.define do
  factory :jabvox_bulk_whatsapp_batch do
    account
    status_jabvox { 'completed' }
    mode_jabvox { 'template' }
  end

  factory :jabvox_bulk_whatsapp_recipient do
    account
    batch { create(:jabvox_bulk_whatsapp_batch, account: account) }
    name_jabvox { 'Mel' }
    phone_number_jabvox { '+573001112233' }
    status_jabvox { 'sent' }
  end
end
