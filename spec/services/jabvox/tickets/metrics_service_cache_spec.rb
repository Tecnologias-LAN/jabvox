require 'rails_helper'

RSpec.describe Jabvox::Tickets::MetricsService do
  let(:account) { create(:account) }
  let(:scope) { account.jabvox_tickets }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  describe '.cached' do
    it 'sirve el mismo resultado desde caché sin recalcular' do
      first = described_class.cached(scope, account_id: account.id, discriminator: 'staff')
      allow(described_class).to receive(:new).and_call_original

      described_class.cached(scope, account_id: account.id, discriminator: 'staff')
      expect(described_class).not_to have_received(:new) # segundo hit no recalcula
      expect(first).to be_a(Hash)
    end

    it 'invalida la caché cuando cambia un ticket (touch_cache!)' do
      described_class.cached(scope, account_id: account.id, discriminator: 'staff')
      key_before = described_class.cache_key(account.id, 'staff')

      described_class.touch_cache!(account.id)
      key_after = described_class.cache_key(account.id, 'staff')

      expect(key_after).not_to eq(key_before)
    end

    it 'usa claves distintas por discriminante de permiso' do
      staff_key = described_class.cache_key(account.id, 'staff')
      user_key = described_class.cache_key(account.id, 'user_5')
      expect(staff_key).not_to eq(user_key)
    end
  end
end
