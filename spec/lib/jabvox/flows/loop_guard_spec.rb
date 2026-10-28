# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Flows::LoopGuard do
  let(:account) { create(:account) }
  let(:flow) { JabvoxFlow.create!(account: account, name: 'Flujo', status: :active) }

  def version_for(flw)
    v = JabvoxFlowVersion.create!(flow: flw, version: 1, graph: { 'nodes' => [], 'edges' => [] })
    flw.update!(current_version: v)
    v
  end

  before do
    version_for(flow)
    # Redis limpio para este flow.
    Redis::Alfred.delete(format(Redis::RedisKeys::JABVOX_FLOW_RUN_RATE, flow_id: flow.id))
    Redis::Alfred.delete(format(Redis::RedisKeys::JABVOX_FLOW_LOOP_NOTIFIED, flow_id: flow.id))
  end

  describe '.record_and_count' do
    it 'incrementa el contador en cada llamada' do
      expect(described_class.record_and_count(flow.id)).to eq(1)
      expect(described_class.record_and_count(flow.id)).to eq(2)
      expect(described_class.record_and_count(flow.id)).to eq(3)
    end

    it 'fija un TTL en la primera llamada (no permanente)' do
      described_class.record_and_count(flow.id)
      ttl = Redis::Alfred.ttl(format(Redis::RedisKeys::JABVOX_FLOW_RUN_RATE, flow_id: flow.id))
      expect(ttl).to be > 0
      expect(ttl).to be <= described_class::WINDOW
    end
  end

  describe '.tripped?' do
    it 'devuelve false mientras no se supere el umbral' do
      (described_class::THRESHOLD - 1).times do
        expect(described_class.tripped?(flow)).to be(false)
      end
      expect(flow.reload).to be_active
    end

    it 'auto-pausa el flujo y devuelve true al superar el umbral' do
      described_class::THRESHOLD.times { described_class.tripped?(flow) }
      expect(described_class.tripped?(flow)).to be(true) # la que cruza el umbral
      expect(flow.reload).to be_paused
    end

    it 'deja un run-centinela con el motivo al auto-pausar' do
      (described_class::THRESHOLD + 1).times { described_class.tripped?(flow) }
      sentinel = account.jabvox_flow_runs.where(flow_id: flow.id, status: :failed).last
      expect(sentinel).to be_present
      expect(sentinel.error).to include('anti-bucle')
    end

    it 'es fail-open: si Redis falla, no bloquea el disparo' do
      allow(Redis::Alfred).to receive(:incr).and_raise(StandardError.new('redis caído'))
      expect(described_class.tripped?(flow)).to be(false)
      expect(flow.reload).to be_active
    end

    it 'aísla el conteo entre flujos distintos' do
      other = JabvoxFlow.create!(account: account, name: 'Otro', status: :active)
      version_for(other)
      described_class::THRESHOLD.times { described_class.tripped?(flow) }
      described_class.tripped?(flow) # satura el primero
      expect(described_class.tripped?(other)).to be(false)
      expect(other.reload).to be_active
    end
  end

  describe '.trip!' do
    it 'es idempotente: no re-pausa un flujo ya pausado' do
      flow.update!(status: :paused)
      expect { described_class.trip!(flow, 999) }
        .not_to(change { account.jabvox_flow_runs.where(status: :failed).count })
    end
  end
end
