# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::ClinicaJwtIssuer do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, name: 'Jane Agent', email: 'jane@example.com') }

  describe '.issue' do
    context 'when JWT_HS256_SECRET is configured' do
      around do |example|
        with_modified_env(JWT_HS256_SECRET: 'test-shared-secret') { example.run }
      end

      it 'encodes the contracted claims' do
        token = described_class.issue(user: user, account: account)
        decoded = JWT.decode(token, 'test-shared-secret', true, algorithm: 'HS256').first

        expect(decoded['account_id']).to eq(account.id)
        expect(decoded['sub']).to eq(user.id.to_s)
        expect(decoded['iss']).to eq('jabvox-core')
        expect(decoded['name']).to eq('Jane Agent')
        expect(decoded['email']).to eq('jane@example.com')
        expect(decoded['iat']).to be_present
        expect(decoded['exp']).to be_present
      end

      it 'defaults the expiry to 24 hours from issuance' do
        travel_to Time.zone.at(1_700_000_000) do
          token = described_class.issue(user: user, account: account)
          decoded = JWT.decode(token, 'test-shared-secret', true, algorithm: 'HS256').first

          expect(decoded['iat']).to eq(1_700_000_000)
          expect(decoded['exp']).to eq(1_700_000_000 + 24.hours.to_i)
        end
      end

      it 'accepts a configurable expiry' do
        token = described_class.issue(user: user, account: account, expires_in: 1.hour)
        decoded = JWT.decode(token, 'test-shared-secret', true, algorithm: 'HS256').first

        expect(decoded['exp'] - decoded['iat']).to eq(1.hour.to_i)
      end

      it 'cannot be decoded with the wrong secret' do
        token = described_class.issue(user: user, account: account)

        expect do
          JWT.decode(token, 'wrong-secret', true, algorithm: 'HS256')
        end.to raise_error(JWT::VerificationError)
      end
    end

    context 'when JWT_HS256_SECRET is not configured' do
      around do |example|
        with_modified_env(JWT_HS256_SECRET: nil) { example.run }
      end

      it 'raises a clear error instead of falling back to a hardcoded secret' do
        expect do
          described_class.issue(user: user, account: account)
        end.to raise_error(/JWT_HS256_SECRET/)
      end
    end
  end
end
