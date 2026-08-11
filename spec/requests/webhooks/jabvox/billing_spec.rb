# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Webhooks::Jabvox::Billing', type: :request do
  describe 'POST /webhooks/jabvox/billing/:gateway' do
    # Config activa que set_gateway busca por find_by(provider:, active:) antes de build.
    let!(:gateway_config) { create(:jabvox_payment_gateway_config, provider: 'bold', active: true) } # rubocop:disable RSpec/LetSetup
    let(:gateway) { instance_double(Jabvox::Billing::Gateways::Bold, provider: 'bold') }

    before do
      allow(Jabvox::Billing::Gateways::Base).to receive(:build).and_return(gateway)
    end

    context 'without an active gateway for that provider' do
      it 'responde 404' do
        post '/webhooks/jabvox/billing/wompi', params: { any: 'thing' }, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with an invalid signature' do
      it 'rechaza el webhook con 401 (no confía en el payload)' do
        allow(gateway).to receive(:verify_webhook_signature).and_return(false)

        post '/webhooks/jabvox/billing/bold', params: { data: { reference: 'x' } }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a valid signature and approved payment' do
      let(:plan) { create(:jabvox_plan, price_cents: 500_000) }
      let!(:transaction) do
        create(:jabvox_provisioning_transaction, gateway: 'bold', gateway_reference: 'ref-1',
                                                 jabvox_plan: plan, amount_cents: 500_000,
                                                 idempotency_key: 'idem-ok', status: :payment_pending)
      end

      before do
        allow(gateway).to receive(:verify_webhook_signature).and_return(true)
        allow(gateway).to receive(:parse_webhook_event)
          .and_return({ approved: true, rejected: false, status: 'SALE_APPROVED',
                        reference: 'idem-ok', payment_id: 'P1', amount_cents: 500_000 })
        # Doble verificación: estado real coincide.
        allow(gateway).to receive(:fetch_payment_status)
          .and_return({ approved: true, status: 'APPROVED', reference: 'ref-1', amount_cents: 500_000 })
      end

      it 'marca el pago aprobado y encola el aprovisionamiento' do
        expect(Jabvox::Billing::ProvisioningJob).to receive(:perform_later).with(transaction.id)

        post '/webhooks/jabvox/billing/bold', params: { any: 'payload' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(transaction.reload).to be_payment_approved
      end
    end

    context 'with a valid signature but a mismatched amount (intento de fraude)' do
      let(:plan) { create(:jabvox_plan, price_cents: 500_000) }
      let!(:transaction) do
        create(:jabvox_provisioning_transaction, gateway: 'bold', jabvox_plan: plan,
                                                 amount_cents: 500_000, idempotency_key: 'idem-bad',
                                                 status: :payment_pending)
      end

      before do
        allow(gateway).to receive(:verify_webhook_signature).and_return(true)
        allow(gateway).to receive(:parse_webhook_event)
          .and_return({ approved: true, rejected: false, status: 'SALE_APPROVED',
                        reference: 'idem-bad', payment_id: 'P2', amount_cents: 100 }) # monto alterado
      end

      it 'rechaza el pago por monto que no coincide con el plan y NO aprovisiona' do
        expect(Jabvox::Billing::ProvisioningJob).not_to receive(:perform_later)

        post '/webhooks/jabvox/billing/bold', params: { any: 'payload' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(transaction.reload).to be_payment_rejected_invalid
      end
    end

    context 'with a valid signature but payment NOT approved' do
      let!(:transaction) do
        create(:jabvox_provisioning_transaction, gateway: 'bold', idempotency_key: 'idem-rej',
                                                 status: :payment_pending)
      end

      before do
        allow(gateway).to receive(:verify_webhook_signature).and_return(true)
        allow(gateway).to receive(:parse_webhook_event)
          .and_return({ approved: false, rejected: true, status: 'SALE_REJECTED',
                        reference: 'idem-rej', payment_id: nil, amount_cents: nil })
      end

      it 'marca la transacción como rechazada por pago inválido' do
        post '/webhooks/jabvox/billing/bold', params: { any: 'payload' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(transaction.reload).to be_payment_rejected_invalid
      end
    end
  end
end
