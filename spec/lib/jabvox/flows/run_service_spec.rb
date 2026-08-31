# frozen_string_literal: true

require 'rails_helper'

# Recorrido COMPLETO contra la base de datos: el run y su traza por paso, con el
# sellado de la iteración que permite inspeccionar cada vuelta del bucle.
RSpec.describe Jabvox::Flows::RunService do
  let(:account) { create(:account) }
  # Bucle de 3 elementos con un paso dentro y un cierre en la rama 'done'.
  let(:graph) do
    { 'nodes' => [
        { 'id' => 't', 'type' => 'trigger.manual' },
        { 'id' => 'bucle', 'type' => 'logic.loop',
          'params' => { 'items' => [{ 'n' => 1 }, { 'n' => 2 }, { 'n' => 3 }] } },
        { 'id' => 'cuerpo', 'type' => 'logic.if',
          'params' => { 'left' => '{{item.n}}', 'operator' => 'greater_than', 'right' => 0 } },
        { 'id' => 'fin', 'type' => 'logic.if',
          'params' => { 'left' => 1, 'operator' => 'equals', 'right' => 1 } }
      ],
      'edges' => [
        { 'id' => 'e1', 'source' => 't', 'target' => 'bucle' },
        { 'id' => 'e2', 'source' => 'bucle', 'target' => 'cuerpo', 'sourceHandle' => 'loop' },
        { 'id' => 'e3', 'source' => 'bucle', 'target' => 'fin', 'sourceHandle' => 'done' }
      ] }
  end
  let(:flow) { JabvoxFlow.create!(account: account, name: 'Flujo de prueba') }

  def build_run(graph)
    version = JabvoxFlowVersion.create!(flow: flow, version: 1, graph: graph)
    flow.update!(current_version: version)
    JabvoxFlowRun.create!(account: account, flow: flow, version: version, trigger: { 'origen' => 'test' })
  end

  it 'persiste el run como success y un paso por iteración' do
    run = build_run(graph)

    expect(described_class.new(run).call).to eq(:success)
    expect(run.reload).to be_success
    expect(run.finished_at).to be_present
    # 3 vueltas del cuerpo + el cierre de la rama 'done'.
    expect(run.steps.where(node_id: 'cuerpo').count).to eq(3)
    expect(run.steps.where(node_id: 'fin').count).to eq(1)
  end

  it 'sella en cada paso la iteración a la que pertenece' do
    run = build_run(graph)
    described_class.new(run).call

    contexts = run.steps.where(node_id: 'cuerpo').order(:id).map(&:loop_context)
    expect(contexts.map { |c| c['posicion'] }).to eq([1, 2, 3])
    expect(contexts.map { |c| c['loopId'] }.uniq).to eq(['bucle'])
    expect(contexts.map { |c| c['totalElementos'] }.uniq).to eq([3])
  end

  it 'expone el input configurado sin el sello del motor' do
    run = build_run(graph)
    described_class.new(run).call

    step = run.steps.find_by(node_id: 'cuerpo')
    expect(step.configured_input).not_to have_key('__bucle')
    expect(step.configured_input).to include('operator' => 'greater_than')
  end

  it 'marca el run como failed y guarda el motivo cuando el grafo se atasca' do
    # Dos bucles en cadena: el segundo cierra el ciclo hacia el primero.
    atascado = {
      'nodes' => [
        { 'id' => 't', 'type' => 'trigger.manual' },
        { 'id' => 'b1', 'type' => 'logic.loop', 'params' => { 'items' => [{ 'n' => 1 }] } },
        { 'id' => 'b2', 'type' => 'logic.loop', 'params' => { 'items' => [{ 'n' => 1 }] } },
        { 'id' => 'fin', 'type' => 'logic.if', 'params' => { 'left' => 1, 'operator' => 'equals', 'right' => 1 } }
      ],
      'edges' => [
        { 'id' => 'e1', 'source' => 't', 'target' => 'b1' },
        { 'id' => 'e2', 'source' => 'b1', 'target' => 'b2', 'sourceHandle' => 'done' },
        { 'id' => 'e3', 'source' => 'b2', 'target' => 'b1', 'sourceHandle' => 'loop' },
        { 'id' => 'e4', 'source' => 'b2', 'target' => 'fin', 'sourceHandle' => 'done' }
      ]
    }
    run = build_run(atascado)

    expect(described_class.new(run).call).to eq(:failed)
    # Falla CERRADO en vez de terminar en verde habiendo perdido pasos.
    expect(run.reload.error).to match(/sin ejecutar aunque estaban conectados/)
  end

  it 'redacta los valores secretos en la traza persistida' do
    JabvoxFlowAccountVariable.create!(account: account, key: 'api_key', value: 'sk-secreto-123', secret: true)
    con_secreto = {
      'nodes' => [
        { 'id' => 't', 'type' => 'trigger.manual' },
        { 'id' => 'paso', 'type' => 'logic.if',
          'params' => { 'left' => '{{global.api_key}}', 'operator' => 'is_not_empty' } }
      ],
      'edges' => [{ 'id' => 'e1', 'source' => 't', 'target' => 'paso' }]
    }
    run = build_run(con_secreto)
    described_class.new(run).call

    # El secreto interpolado no debe quedar legible en el historial.
    expect(run.steps.find_by(node_id: 'paso').input.to_json).not_to include('sk-secreto-123')
  end
end
