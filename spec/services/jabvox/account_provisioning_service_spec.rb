# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::AccountProvisioningService do
  let(:base) { { email: 'nuevo@empresa.com', name: 'Empresa X' } }

  describe '#call' do
    it 'crea la cuenta y su usuario administrador' do
      result = described_class.new(**base).call

      expect(result[:account]).to be_persisted
      expect(result[:account].name).to eq('Empresa X')
      expect(result[:user].email).to eq('nuevo@empresa.com')
      expect(result[:created_user]).to be(true)
      au = result[:account].account_users.find_by(user_id: result[:user].id)
      expect(au.role).to eq('administrator')
    end

    it 'activa los módulos Jabvox indicados (columnas booleanas)' do
      result = described_class.new(**base, modules: %w[tickets kanban analytics]).call
      account = result[:account]

      expect(account.jabvox_tickets_enabled_jabvox).to be(true)
      expect(account.jabvox_kanban_enabled_jabvox).to be(true)
      expect(account.jabvox_analytics_enabled_jabvox).to be(true)
      expect(account.jabvox_sms_enabled_jabvox).to be(false) # no pedido
    end

    it 'activa las features nativas de Chatwoot indicadas' do
      result = described_class.new(**base, features: %w[crm help_center]).call
      account = result[:account]

      expect(account.feature_enabled?('crm')).to be(true)
      expect(account.feature_enabled?('help_center')).to be(true)
    end

    it 'rechaza features de Chatwoot desconocidas' do
      expect { described_class.new(**base, features: %w[inexistente]).call }
        .to raise_error(described_class::ProvisioningError, /features desconocidas/)
    end

    it 'devuelve un link seguro de establecer-contraseña (token temporal, sin password)' do
      result = described_class.new(**base, base_url: 'https://app.jabvox.com').call
      url = result[:set_password_url]

      expect(url).to start_with('https://app.jabvox.com/app/auth/password/edit?reset_password_token=')
      expect(url).not_to include(result[:user].password.to_s) # nunca la contraseña
    end

    it 'fija los límites de accounts.limits (inboxes/agents/ai_documents/rules/dashboards)' do
      result = described_class.new(
        **base,
        limits: { inboxes: 5, agents: 10, ai_documents: 100,
                  automation_rules: 20, analytics_dashboards: 3 }
      ).call
      limits = result[:account].limits

      expect(limits['inboxes']).to eq(5)
      expect(limits['agents']).to eq(10)
      expect(limits['ai_documents']).to eq(100)
      expect(limits['automation_rules']).to eq(20)
      expect(limits['analytics_dashboards']).to eq(3)
    end

    it 'fija el límite de formularios (max_forms_jabvox)' do
      result = described_class.new(**base, limits: { forms: 7 }).call
      expect(result[:account].max_forms_jabvox).to eq(7)
    end

    it 'fija el límite de flujos de automatización avanzada (max_flows)' do
      result = described_class.new(**base, limits: { advanced_flows: 5 }).call
      expect(result[:account].account_automation_config.max_flows).to eq(5)
    end

    it 'reutiliza un usuario existente en vez de duplicarlo' do
      existing = create(:user, email: 'nuevo@empresa.com')
      result = described_class.new(**base).call

      expect(result[:user].id).to eq(existing.id)
      expect(result[:created_user]).to be(false)
    end

    it 'rechaza email inválido' do
      expect { described_class.new(email: 'no-es-email').call }
        .to raise_error(described_class::ProvisioningError, /email/)
    end

    it 'rechaza módulos desconocidos' do
      expect { described_class.new(**base, modules: %w[inexistente]).call }
        .to raise_error(described_class::ProvisioningError, /desconocido/)
    end

    it 'es idempotente: la misma idempotency_key no duplica la cuenta' do
      first = described_class.new(**base, idempotency_key: 'pago-123').call
      second = nil
      expect do
        second = described_class.new(**base, idempotency_key: 'pago-123').call
      end.not_to change(Account, :count)

      expect(second[:account].id).to eq(first[:account].id)
      expect(second[:replayed]).to be(true)
      expect(second[:set_password_url]).to be_nil # no se regenera el token en el reintento
    end

    it 'es atómico: si el módulo es inválido, no crea la cuenta' do
      expect do
        described_class.new(**base, modules: %w[inexistente]).call
      rescue described_class::ProvisioningError
        nil
      end.not_to change(Account, :count)
    end
  end
end
