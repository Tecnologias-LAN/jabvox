# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::AccountBillingEntitlements do
  describe '#billable_limits_summary' do
    let(:plan) do
      create(
        :jabvox_plan,
        limits: {
          'agents' => { 'included' => 5, 'unit_price_cents' => 10_00 },
          'storage_gb' => { 'included' => 10, 'unit_price_cents' => 3_00 }
        }
      )
    end
    let(:account) do
      create(
        :account,
        jabvox_plan: plan,
        limits: {
          'agents_extra' => 2,
          'agents_unit_price_cents' => 10_00,
          'storage_gb_extra' => 5
        }
      )
    end

    it 'combina plan, extras y precios por cuenta' do
      summary = account.billable_limits_summary

      expect(summary['agents']).to include(included: 5, extra: 2, limit: 7, unit_price_cents: 10_00, extra_price_cents: 20_00)
      expect(summary['storage_gb']).to include(included: 10, extra: 5, limit: 15, unit_price_cents: 3_00, extra_price_cents: 15_00)
      expect(account.billable_extra_cents).to eq(35_00)
    end
  end
end
