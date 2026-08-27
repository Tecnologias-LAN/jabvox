# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Billing::ProvisioningService do
  let(:plan) do
    create(:jabvox_plan, modules: %w[tickets kanban], chatwoot_features: [],
                         limits: { 'agents' => 5, 'forms' => 2 }, duration_days: 30)
  end
  let(:transaction) do
    create(:jabvox_provisioning_transaction, jabvox_plan: plan,
                                             buyer_email: 'nuevo@empresa.com', status: :payment_approved)
  end

  describe '#call' do
    it 'aprovisiona la cuenta con los módulos/límites del plan y fija la expiración' do
      result = described_class.new(transaction).call
      account = result[:account]

      expect(account).to be_persisted
      expect(account.jabvox_tickets_enabled_jabvox).to be(true)
      expect(account.limits['agents']).to eq(5)
      expect(account.jabvox_plan_id).to eq(plan.id)
      expect(account.jabvox_plan_expires_at).to be_within(1.day).of(30.days.from_now)
      expect(transaction.reload).to be_provisioned
    end

    it 'es idempotente: reintentar sobre una transacción ya aprovisionada no duplica cuenta' do
      described_class.new(transaction).call
      account_id = transaction.reload.account_id

      expect { described_class.new(transaction.reload).call }.not_to change(Account, :count)
      expect(transaction.reload.account_id).to eq(account_id)
    end

    it 'no habilita tiempo dos veces (la expiración no se extiende al reintentar)' do
      described_class.new(transaction).call
      first_exp = transaction.reload.account.jabvox_plan_expires_at

      described_class.new(transaction.reload).call
      expect(transaction.reload.account.jabvox_plan_expires_at).to eq(first_exp)
    end

    it 'rechaza si la transacción no está en estado aprovisionable' do
      pending_tx = create(:jabvox_provisioning_transaction, status: :payment_pending)
      expect { described_class.new(pending_tx).call }
        .to raise_error(Jabvox::Billing::ProvisioningError)
    end
  end
end
