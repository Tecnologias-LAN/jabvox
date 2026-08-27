# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Softphone::StatusService do
  let(:account) { create(:account) }

  describe '#call' do
    it 'reporta disabled si el módulo no está activo' do
      result = described_class.new(account).call
      expect(result[:account_status]).to eq(described_class::DISABLED)
    end

    context 'when the module is active' do
      before { account.update!(jabvox_softphone_enabled_jabvox: true) }

      it 'reporta no_config si falta la configuración' do
        result = described_class.new(account).call
        expect(result[:account_status]).to eq(described_class::NO_CONFIG)
      end

      it 'reporta server_missing si la config no está operativa' do
        create(:jabvox_softphone_config, account: account, enabled: true, wss_url: nil, sip_domain: nil)
        result = described_class.new(account).call
        expect(result[:account_status]).to eq(described_class::NOT_CONFIGURED)
      end

      it 'reporta ok y lista las extensiones cuando la config es operativa' do
        create(:jabvox_softphone_config, account: account)
        user = create(:user)
        create(:account_user, account: account, user: user)
        create(:jabvox_user_extension, account: account, user: user, extension_jabvox: '1001')
        create(:jabvox_softphone_extension, account: account, user: user)
        result = described_class.new(account).call

        expect(result[:account_status]).to eq(described_class::OK)
        expect(result[:extensions].first[:extension]).to eq('1001')
      end

      context 'estado en vivo por extensión (presencia reportada por el navegador)' do
        let(:user) { create(:user) }
        let(:ext) { create(:jabvox_softphone_extension, account: account, user: user) }

        before do
          create(:jabvox_softphone_config, account: account)
          create(:account_user, account: account, user: user)
          create(:jabvox_user_extension, account: account, user: user, extension_jabvox: '1001')
        end

        it 'never_connected si nunca reportó presencia' do
          ext.update!(live_state: 'disconnected', last_seen_at: nil)
          result = described_class.new(account).call
          expect(result[:extensions].first[:state]).to eq('never_connected')
        end

        it 'online si el heartbeat reciente reporta registered' do
          ext.update!(live_state: 'registered', last_seen_at: Time.current)
          result = described_class.new(account).call
          expect(result[:extensions].first[:state]).to eq('online')
        end

        it 'on_call si está en llamada' do
          ext.update!(live_state: 'in_call', last_seen_at: Time.current)
          result = described_class.new(account).call
          expect(result[:extensions].first[:state]).to eq('on_call')
        end

        it 'offline si el heartbeat está obsoleto (> ventana), aunque el último estado fuera registered' do
          ext.update!(live_state: 'registered', last_seen_at: (described_class::STALE_AFTER + 30).seconds.ago)
          result = described_class.new(account).call
          expect(result[:extensions].first[:state]).to eq('offline')
        end
      end
    end
  end
end
