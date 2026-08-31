# frozen_string_literal: true

require 'rails_helper'

# SUSPENSIÓN Y REANUDACIÓN de runs: el puntero persistido, la continuación por
# los sucesores del nodo de espera, la semántica del vencimiento y el rechazo
# explícito de una espera DENTRO de un bucle.
RSpec.describe Jabvox::Flows::RunService do
  let(:account) { create(:account) }
  # trigger → espera → después
  let(:graph_espera) do
    { 'nodes' => [
        { 'id' => 't', 'type' => 'trigger.manual' },
        { 'id' => 'espera', 'type' => 'logic.delay',
          'params' => { 'reason' => 'delay', 'resumeAt' => 2.hours.from_now.iso8601 } },
        { 'id' => 'despues', 'type' => 'test.step' }
      ],
      'edges' => [
        { 'id' => 'e1', 'source' => 't', 'target' => 'espera' },
        { 'id' => 'e2', 'source' => 'espera', 'target' => 'despues' }
      ] }
  end
  let(:flow) { JabvoxFlow.create!(account: account, name: 'Flujo con espera') }

  def build_run(graph)
    version = JabvoxFlowVersion.create!(flow: flow, version: 1, graph: graph)
    flow.update!(current_version: version)
    JabvoxFlowRun.create!(account: account, flow: flow, version: version, trigger: { 'origen' => 'test' })
  end

  # Registro de prueba con un nodo de espera; el motor no trae nodos aún.
  def registry
    trace = []
    registry = Jabvox::Flows::Engine::Registry.new
    registry.register('trigger.manual', label: 'Disparador manual')
    registry.register('logic.delay', label: 'Esperar') do |_ctx, _node, params|
      Jabvox::Flows::Engine::NodeResult.ok(
        { 'esperando' => true },
        wait: { 'reason' => params['reason'] || 'delay', 'resumeAt' => params['resumeAt'] }
      )
    end
    registry.register('test.step', label: 'Paso') do |ctx, node, _params|
      trace << node.id
      Jabvox::Flows::Engine::NodeResult.ok({ 'visto' => ctx.vars['resume'] })
    end
    registry.register('logic.loop', label: 'Bucle', outputs: %w[loop done]) do |_ctx, _node, params|
      Jabvox::Flows::Engine::NodeResult.ok(params.slice('items', 'itemVar', 'onItemError'))
    end
    registry
  end

  describe 'suspensión' do
    it 'deja el run en waiting con el puntero de reanudación completo' do
      run = build_run(graph_espera)

      expect(described_class.new(run, registry: registry).call).to eq(:waiting)

      run.reload
      expect(run).to be_waiting
      expect(run.waiting_node_id).to eq('espera')
      expect(run.wait_reason).to eq('delay')
      expect(run.resume_at).to be_present
      # Un run suspendido NO ha terminado.
      expect(run.finished_at).to be_nil
    end

    it 'NO ejecuta los pasos posteriores a la espera' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call

      expect(run.reload.steps.pluck(:node_id)).to contain_exactly('espera')
      expect(run.steps.find_by(node_id: 'espera')).to be_waiting
    end

    it 'guarda en wait_state el snapshot del contexto, sin las globales' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call

      state = run.reload.wait_state
      expect(state.keys).to contain_exactly('vars', 'outputs', 'trigger')
      expect(state['trigger']).to eq('origen' => 'test')
      expect(state['outputs']).to have_key('espera')
    end

    it 'programa el despertador puntual para el instante de reanudación' do
      run = build_run(graph_espera)

      expect { described_class.new(run, registry: registry).call }
        .to have_enqueued_job(Jabvox::Flows::ResumeRunJob).with(run.id)
    end
  end

  describe 'reanudación' do
    it 'continúa por los sucesores del nodo de espera y termina en success' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call

      expect(described_class.new(run.reload, registry: registry).resume).to eq(:success)

      run.reload
      expect(run).to be_success
      expect(run.finished_at).to be_present
      expect(run.steps.pluck(:node_id)).to include('despues')
    end

    it 'limpia el puntero de reanudación al continuar' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call
      described_class.new(run.reload, registry: registry).resume

      run.reload
      expect(run.waiting_node_id).to be_nil
      expect(run.wait_reason).to be_nil
      expect(run.resume_at).to be_nil
      expect(run.wait_state).to be_nil
    end

    it 'cierra el paso en espera en vez de dejarlo waiting para siempre' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call
      described_class.new(run.reload, registry: registry).resume(payload: { 'ok' => true })

      step = run.reload.steps.find_by(node_id: 'espera')
      expect(step).to be_success
      expect(step.output).to include('response' => { 'ok' => true }, 'timedOut' => false)
    end

    it 'publica la respuesta como {{vars.resume}} y como salida del nodo de espera' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call
      described_class.new(run.reload, registry: registry).resume(payload: { 'codigo' => 'A1' })

      # El paso posterior leyó ctx.vars['resume'].
      expect(run.reload.steps.find_by(node_id: 'despues').output).to eq('visto' => { 'codigo' => 'A1' })
    end

    it 'restaura vars y outputs del snapshot al reanudar' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call
      described_class.new(run.reload, registry: registry).resume

      # El output del nodo de espera venía del snapshot y sigue ahí, enriquecido.
      expect(run.reload.steps.find_by(node_id: 'espera').output).to include('esperando' => true)
    end

    it 'no reanuda dos veces: el segundo despertar no ejecuta nada' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call
      described_class.new(run.reload, registry: registry).resume

      # El run ya no está waiting: la toma de posesión atómica falla.
      expect(described_class.new(run.reload, registry: registry).resume).to eq(:not_waiting)
      expect(run.reload.steps.where(node_id: 'despues').count).to eq(1)
    end

    it 'rechaza reanudar un run que no está en espera' do
      run = build_run(graph_espera)

      expect(described_class.new(run, registry: registry).resume).to eq(:not_waiting)
    end
  end

  describe 'semántica del vencimiento' do
    let(:graph_respuesta) do
      graph = graph_espera.deep_dup
      graph['nodes'][1]['params']['reason'] = 'wait_response'
      graph
    end

    it 'falla el run cuando vence una espera de RESPUESTA sin respuesta' do
      run = build_run(graph_respuesta)
      described_class.new(run, registry: registry).call

      expect(described_class.new(run.reload, registry: registry).resume(timed_out: true)).to eq(:failed)

      run.reload
      expect(run).to be_failed
      expect(run.error).to include('Se agotó el tiempo de espera de respuesta')
      # NO se continúa por la rama siguiente.
      expect(run.steps.pluck(:node_id)).not_to include('despues')
      expect(run.steps.find_by(node_id: 'espera')).to be_failed
    end

    it 'continúa con normalidad cuando vence un delay (el plazo ES el evento)' do
      run = build_run(graph_espera)
      described_class.new(run, registry: registry).call

      expect(described_class.new(run.reload, registry: registry).resume(timed_out: false)).to eq(:success)
      expect(run.reload.steps.pluck(:node_id)).to include('despues')
    end
  end

  describe 'BUG: espera DENTRO de un bucle' do
    # El bucle recorre su rama por elemento; la reanudación no sabe reconstruir
    # el estado de la iteración (elemento en curso, contadores, lote).
    let(:graph_bucle) do
      { 'nodes' => [
          { 'id' => 't', 'type' => 'trigger.manual' },
          { 'id' => 'bucle', 'type' => 'logic.loop',
            'params' => { 'items' => [{ 'n' => 1 }, { 'n' => 2 }] } },
          { 'id' => 'espera', 'type' => 'logic.delay',
            'params' => { 'reason' => 'delay', 'resumeAt' => 1.hour.from_now.iso8601 } },
          { 'id' => 'fin', 'type' => 'test.step' }
        ],
        'edges' => [
          { 'id' => 'e1', 'source' => 't', 'target' => 'bucle' },
          { 'id' => 'e2', 'source' => 'bucle', 'target' => 'espera', 'sourceHandle' => 'loop' },
          { 'id' => 'e3', 'source' => 'bucle', 'target' => 'fin', 'sourceHandle' => 'done' }
        ] }
    end

    it 'falla explícitamente en vez de suspender o de omitir la espera en silencio' do
      run = build_run(graph_bucle)

      expect(described_class.new(run, registry: registry).call).to eq(:failed)

      run.reload
      expect(run).to be_failed
      expect(run.error).to include('no están soportados dentro de un bucle')
      expect(run.error).to include('saca la espera fuera del bucle')
      # El run NO queda suspendido: no hay puntero de reanudación.
      expect(run.waiting_node_id).to be_nil
      expect(run.status).not_to eq('waiting')
    end

    it 'NO deja el paso de espera en waiting para siempre' do
      run = build_run(graph_bucle)
      described_class.new(run, registry: registry).call

      steps = run.reload.steps.where(node_id: 'espera')
      expect(steps).to be_present
      expect(steps.map(&:status).uniq).to eq(['failed'])
      expect(steps.first.error).to include('dentro de un bucle')
    end
  end
end
