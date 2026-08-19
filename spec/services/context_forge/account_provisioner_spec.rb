# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContextForge::AccountProvisioner do
  let(:account) { create(:account) }

  # Doble de ContextForge::Service que responde OK y rastrea las MCPs creadas por cuenta.
  let(:fake_service) do
    result = ContextForge::Service::Result
    Class.new do
      define_method(:result_class) { result }
      attr_reader :mcps

      def initialize
        @mcps = []
      end

      def ensure_team(account) = result_class.new(success: true, data: { 'id' => "team-#{account.id}" })

      def ensure_mcp_server(account, **opts)
        @mcps << opts[:kind]
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
    allow(ContextForge::Service).to receive(:configured?).and_return(true)
    allow(ContextForge::Service).to receive(:base_url).and_return('https://cf.example/api')
  end

  describe '#call' do
    it 'aprovisiona la cuenta de punta a punta y persiste el handoff listo' do
      result = described_class.new(account, service: fake_service).call

      expect(result).to be_success
      handoff = account.reload.jabvox_context_forge_handoff
      expect(handoff.status).to eq('ready')
      expect(handoff.virtual_server_id).to eq("vs-#{account.id}")
      expect(handoff.scoped_token).to eq("tok-#{account.id}")
      expect(handoff).to be_operational
      expect(handoff.mcp_servers.size).to eq(described_class::DEFAULT_MCPS.size)
    end

    it 'es idempotente: re-ejecutar no crea un segundo handoff' do
      described_class.new(account, service: fake_service).call
      described_class.new(account, service: fake_service).call
      expect(JabvoxContextForgeHandoff.where(account_id: account.id).count).to eq(1)
    end

    it 'marca failed y guarda el motivo si una etapa falla' do
      failing = fake_service
      allow(failing).to receive(:ensure_virtual_server)
        .and_return(ContextForge::Service::Result.new(success: false, error: 'boom'))

      result = described_class.new(account, service: failing).call

      expect(result).not_to be_success
      handoff = account.reload.jabvox_context_forge_handoff
      expect(handoff.status).to eq('failed')
      expect(handoff.last_error).to include('boom')
    end

    it 'no hace nada si ContextForge no está configurado' do
      allow(ContextForge::Service).to receive(:configured?).and_return(false)
      result = described_class.new(account, service: fake_service).call
      expect(result).not_to be_success
      expect(result.error).to include('no está configurado')
    end
  end
end
