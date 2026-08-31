# frozen_string_literal: true

require 'rails_helper'

# Barrido por minuto: qué flujos programados se encolan y cuáles no.
RSpec.describe Jabvox::Flows::TriggerScheduledFlowsJob do
  let(:account) { create(:account) }
  # 14:00 UTC = 09:00 en Bogotá.
  let(:instante) { Time.utc(2026, 8, 27, 14, 0) }

  def build_flow(params, status: :active)
    flow = JabvoxFlow.create!(account: account, name: 'Programado', status: status)
    version = JabvoxFlowVersion.create!(
      flow: flow, version: 1,
      graph: { 'nodes' => [{ 'id' => 'p', 'type' => 'trigger.schedule', 'params' => params }], 'edges' => [] }
    )
    flow.update!(current_version: version)
    flow
  end

  before { allow(Redis::Alfred).to receive(:set).and_return(true) }

  it 'encola un run del flujo al que le toca en SU zona horaria' do
    flow = build_flow({ 'mode' => 'daily', 'time' => '09:00', 'timezone' => 'America/Bogota' })

    travel_to(instante) { described_class.perform_now }

    expect(flow.runs.count).to eq(1)
    expect(flow.runs.first.trigger).to include('tipo' => 'trigger.schedule', 'nodeId' => 'p')
  end

  it 'no encola nada cuando no le toca' do
    flow = build_flow({ 'mode' => 'daily', 'time' => '23:00', 'timezone' => 'America/Bogota' })

    travel_to(instante) { described_class.perform_now }

    expect(flow.runs.count).to eq(0)
  end

  it 'ignora los flujos que no están activos' do
    flow = build_flow({ 'mode' => 'daily', 'time' => '09:00', 'timezone' => 'America/Bogota' },
                      status: :draft)

    travel_to(instante) { described_class.perform_now }

    expect(flow.runs.count).to eq(0)
  end

  it 'no dispara dos veces el mismo minuto' do
    flow = build_flow({ 'mode' => 'daily', 'time' => '09:00', 'timezone' => 'America/Bogota' })
    # El segundo intento no gana el candado.
    allow(Redis::Alfred).to receive(:set).and_return(true, false)

    travel_to(instante) do
      described_class.perform_now
      described_class.perform_now
    end

    expect(flow.runs.count).to eq(1)
  end
end
