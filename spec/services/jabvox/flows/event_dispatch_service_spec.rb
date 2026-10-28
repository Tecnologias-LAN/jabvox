# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Flows::EventDispatchService do
  let(:account) { create(:account) }

  before do
    # El módulo Advanced Automations se gatea por una columna propia del account,
    # no por el bitmask de features.yml.
    account.update!(jabvox_advanced_automations_enabled_jabvox: true)
  end

  # Flujo activo cuyo trigger.jabvox_event matchea cualquier evento de contacto.
  def active_flow_matching(event:)
    flow = JabvoxFlow.create!(account: account, name: "Flow #{event}", status: :active)
    graph = {
      'nodes' => [{ 'id' => 't', 'type' => 'trigger.jabvox_event',
                    'data' => { 'params' => { 'event' => event } } }],
      'edges' => []
    }
    version = JabvoxFlowVersion.create!(flow: flow, version: 1, graph: graph)
    flow.update!(current_version: version)
    flow
  end

  def dispatch(event: 'contact_created')
    described_class.new(account: account, event_name: event, payload: { 'id' => 1 }).call
  end

  def clear_guard(flow)
    Redis::Alfred.delete(format(Redis::RedisKeys::JABVOX_FLOW_RUN_RATE, flow_id: flow.id))
    Redis::Alfred.delete(format(Redis::RedisKeys::JABVOX_FLOW_LOOP_NOTIFIED, flow_id: flow.id))
  end

  describe 'guardia anti-bucle' do
    let!(:flow) { active_flow_matching(event: 'contact_created') }

    before { clear_guard(flow) }

    it 'encola runs mientras no se supere el umbral' do
      expect do
        (Jabvox::Flows::LoopGuard::THRESHOLD - 1).times { dispatch }
      end.to change { account.jabvox_flow_runs.where(flow_id: flow.id, status: :pending).count }
        .by(Jabvox::Flows::LoopGuard::THRESHOLD - 1)
      expect(flow.reload).to be_active
    end

    it 'deja de encolar y auto-pausa el flujo al superar el umbral' do
      (Jabvox::Flows::LoopGuard::THRESHOLD + 5).times { dispatch }

      pending_runs = account.jabvox_flow_runs.where(flow_id: flow.id, status: :pending).count
      # Nunca más de THRESHOLD runs reales (los de más allá del umbral se saltan).
      expect(pending_runs).to be <= Jabvox::Flows::LoopGuard::THRESHOLD
      expect(flow.reload).to be_paused
    end

    it 'una vez pausado ya no vuelve a matchear (matching_flows solo mira activos)' do
      (Jabvox::Flows::LoopGuard::THRESHOLD + 1).times { dispatch }
      expect(flow.reload).to be_paused

      expect { dispatch }
        .not_to(change { account.jabvox_flow_runs.where(flow_id: flow.id, status: :pending).count })
    end

    it 'es fail-open: si Redis falla, sigue encolando (no bloquea tráfico legítimo)' do
      allow(Redis::Alfred).to receive(:incr).and_raise(StandardError.new('redis caído'))
      expect { dispatch }
        .to change { account.jabvox_flow_runs.where(flow_id: flow.id, status: :pending).count }.by(1)
      expect(flow.reload).to be_active
    end
  end

  describe 'aislamiento entre flujos' do
    it 'saturar un flujo no afecta a otro' do
      flow_a = active_flow_matching(event: 'contact_created')
      flow_b = active_flow_matching(event: 'contact_created')
      clear_guard(flow_a)
      clear_guard(flow_b)

      (Jabvox::Flows::LoopGuard::THRESHOLD + 1).times { dispatch }

      expect(flow_a.reload).to be_paused
      # flow_b recibió el mismo número de disparos; también se pausa (su propio contador).
      # Para probar aislamiento real, un flujo con MENOS disparos debe seguir activo:
      flow_c = active_flow_matching(event: 'conversation_created')
      clear_guard(flow_c)
      described_class.new(account: account, event_name: 'conversation_created', payload: { 'id' => 9 }).call
      expect(flow_c.reload).to be_active
    end
  end
end
