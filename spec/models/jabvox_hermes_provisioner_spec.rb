# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxHermesProvisioner do
  describe '.instance (singleton único)' do
    it 'devuelve siempre el mismo registro' do
      a = described_class.instance
      b = described_class.instance
      expect(a.id).to eq(b.id)
      expect(described_class.count).to eq(1)
    end
  end

  describe '#mark_connected! / #connected?' do
    it 'guarda los 4 datos del agente y queda conectado' do
      p = described_class.instance
      p.mark_connected!(
        base_url: 'http://tu-hermes.ejemplo:9119/p/mi-agente/v1',
        service_token: 'tok-abc', name: 'Agente Aprovisionador', hermes_agent_name: 'mi-agente'
      )
      expect(p.connected?).to be(true)
      expect(p.name_jabvox).to eq('Agente Aprovisionador')
      expect(p.hermes_agent_name_jabvox).to eq('mi-agente')
      expect(p.base_url_jabvox).to eq('http://tu-hermes.ejemplo:9119/p/mi-agente/v1')
    end

    it 'no está conectado sin URL o sin token' do
      p = described_class.new(status_jabvox: 'connected')
      expect(p.connected?).to be(false)
    end

    it 'conserva el nombre si se llama sin nombre nuevo' do
      p = described_class.instance
      p.mark_connected!(base_url: 'http://h.ejemplo/p/a/v1', service_token: 't', name: 'Original')
      p.mark_connected!(base_url: 'http://h.ejemplo/p/a/v1', service_token: 't2')
      expect(p.name_jabvox).to eq('Original')
    end
  end

  describe '#safe_summary' do
    it 'nunca expone el token' do
      p = described_class.instance
      p.mark_connected!(base_url: 'http://h.ejemplo/p/a/v1', service_token: 'super-secreto', hermes_agent_name: 'a')
      summary = p.safe_summary
      expect(summary[:base_url]).to eq('http://h.ejemplo/p/a/v1')
      expect(summary[:hermes_agent_name]).to eq('a')
      expect(summary.values.join).not_to include('super-secreto')
    end
  end
end
