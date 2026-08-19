# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::ProvisioningChatService do
  let(:account) { create(:account) }
  let(:user) { create(:user) }

  let(:fake_service) do
    result = ContextForge::Service::Result
    Class.new do
      define_method(:result_class) { result }
      def ensure_team(account) = result_class.new(success: true, data: { 'id' => "team-#{account.id}" })

      def ensure_mcp_server(account, **opts)
        result_class.new(success: true, data: { 'id' => "mcp-#{account.id}-#{opts[:kind]}" })
      end

      def ensure_virtual_server(account, **_opts)
        result_class.new(success: true, data: { 'id' => "vs-#{account.id}" })
      end

      def issue_scoped_token(account, **_opts)
        result_class.new(success: true, data: { 'token' => "tok-#{account.id}" })
      end
    end.new
  end

  before do
    allow(ContextForge::Service).to receive_messages(configured?: true, base_url: 'https://cf/api',
                                                     hermes_url: '')
  end

  describe '#handle' do
    context 'without provisioned handoff' do
      it 'guía al usuario a aprovisionar primero' do
        out = described_class.new(account: account, user: user, service: fake_service)
                             .handle('crea un mcp de analytics')
        expect(out[:reply]).to include('Aprovisionar')
      end
    end

    context 'with operational handoff' do
      before { create(:jabvox_context_forge_handoff, :ready, account: account) }

      it 'crea un MCP cuando el usuario lo pide por lenguaje natural' do
        out = described_class.new(account: account, user: user, service: fake_service)
                             .handle('por favor crea un MCP de analytics')
        expect(out[:metadata][:action]).to eq('create_mcp')
        expect(out[:metadata][:ok]).to be(true)
        expect(out[:metadata][:kind]).to eq('analytics_db')
      end

      it 'responde con ayuda si no reconoce una intención de crear MCP' do
        out = described_class.new(account: account, user: user, service: fake_service)
                             .handle('hola, qué puedes hacer')
        expect(out[:reply]).to include('MCP')
        expect(out[:metadata][:action]).to be_nil
      end
    end
  end
end
