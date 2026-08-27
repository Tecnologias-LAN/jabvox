# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Billing::CheckoutTokenService do
  describe '.encode / .decode' do
    it 'firma y recupera account_id y plan_id' do
      token = described_class.encode(account_id: 7, plan_id: 3)
      decoded = described_class.decode(token)

      expect(decoded[:account_id]).to eq(7)
      expect(decoded[:plan_id]).to eq(3)
    end

    it 'rechaza un token manipulado' do
      token = described_class.encode(account_id: 7, plan_id: 3)
      expect { described_class.decode("#{token}tampered") }
        .to raise_error(Jabvox::Billing::CheckoutTokenError)
    end

    it 'rechaza un token expirado' do
      token = described_class.encode(account_id: 7, plan_id: 3)
      travel_to(20.minutes.from_now) do
        expect { described_class.decode(token) }
          .to raise_error(Jabvox::Billing::CheckoutTokenError, 'token_expired')
      end
    end

    it 'no expone el account_id en texto plano (va firmado en el JWT)' do
      token = described_class.encode(account_id: 999_888, plan_id: 3)
      expect(token).not_to include('999888')
    end
  end
end
