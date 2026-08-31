# frozen_string_literal: true

require 'rails_helper'

# Modelo de TOKENS POR ARISTA: confluencias, propagación de muerte y el guard
# de parada silenciosa.
RSpec.describe Jabvox::Flows::Engine::Executor do
  describe 'confluencia (diamante)' do
    it 'espera a las DOS ramas antes de ejecutar la confluencia' do
      # A→B→D y A→C→D, con la rama B más larga: D no debe correr con la primera.
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'b1', type: 'test.step' }, { id: 'b2', type: 'test.step' },
          { id: 'c1', type: 'test.step' },
          { id: 'd', type: 'logic.merge' }
        ],
        edges: [
          { source: 't', target: 'b1' }, { source: 'b1', target: 'b2' },
          { source: 'b2', target: 'd' },
          { source: 't', target: 'c1' }, { source: 'c1', target: 'd' }
        ]
      )
      status, trace = run_engine(graph)

      order = trace.map { |t| t[:node] }
      expect(status).to eq(:success)
      expect(order.count('d')).to eq(1)
      # La confluencia va después de AMBAS ramas, incluida la larga.
      expect(order.index('d')).to be > order.index('b2')
      expect(order.index('d')).to be > order.index('c1')
    end
  end

  describe 'ramas no tomadas de un IF' do
    it 'termina en success cuando la rama falsa NO está conectada' do
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'si', type: 'logic.if',
            params: { 'left' => 1, 'operator' => 'equals', 'right' => 2 } },
          { id: 'verdadero', type: 'test.step' }
        ],
        edges: [
          { source: 't', target: 'si' },
          { source: 'si', target: 'verdadero', sourceHandle: 'true' }
        ]
      )
      status, trace = run_engine(graph)

      # La condición es falsa y la rama 'false' no existe: el run no se cuelga.
      expect(status).to eq(:success)
      expect(trace.map { |t| t[:node] }).not_to include('verdadero')
    end

    it 'propaga la muerte en cascada sin colgar una confluencia aguas abajo' do
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'si', type: 'logic.if',
            params: { 'left' => 1, 'operator' => 'equals', 'right' => 1 } },
          { id: 'rama_v', type: 'test.step' },
          { id: 'rama_f1', type: 'test.step' }, { id: 'rama_f2', type: 'test.step' },
          { id: 'union', type: 'logic.merge' }
        ],
        edges: [
          { source: 't', target: 'si' },
          { source: 'si', target: 'rama_v', sourceHandle: 'true' },
          { source: 'si', target: 'rama_f1', sourceHandle: 'false' },
          { source: 'rama_f1', target: 'rama_f2' },
          { source: 'rama_v', target: 'union' }, { source: 'rama_f2', target: 'union' }
        ]
      )
      status, trace = run_engine(graph)

      order = trace.map { |t| t[:node] }
      expect(status).to eq(:success)
      # La rama falsa muere en cascada y la confluencia corre igual.
      expect(order).to include('rama_v', 'union')
      expect(order).not_to include('rama_f1', 'rama_f2')
    end
  end

  describe 'guard de parada silenciosa' do
    it 'FALLA cuando dos bucles en cadena dejan un paso conectado sin ejecutar' do
      # El segundo bucle cierra el ciclo hacia el primero por su puerto 'loop':
      # ese retorno es arista de retroceso, el primer bucle queda fuera del
      # recorrido y nada entrega su token a FIN. Antes el run decía «correcto»
      # sin ejecutar ni un paso.
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'bucle1', type: 'logic.loop', params: { 'items' => [{ 'n' => 1 }] } },
          { id: 'bucle2', type: 'logic.loop', params: { 'items' => [{ 'n' => 1 }] } },
          { id: 'fin', type: 'test.step' }
        ],
        edges: [
          { source: 't', target: 'bucle1' },
          { source: 'bucle1', target: 'bucle2', sourceHandle: 'done' },
          { source: 'bucle2', target: 'bucle1', sourceHandle: 'loop' },
          { source: 'bucle2', target: 'fin', sourceHandle: 'done' }
        ]
      )

      expect { run_engine(graph) }
        .to raise_error(Jabvox::Flows::Engine::ExecutionError, /sin ejecutar aunque estaban conectados/)
    end

    it 'NO da falso positivo en una confluencia legítima' do
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'p', type: 'test.step' },
          { id: 'm', type: 'logic.merge' },
          { id: 'fin', type: 'test.step' }
        ],
        edges: [
          { source: 't', target: 'p' }, { source: 'p', target: 'm' },
          { source: 't', target: 'm' }, { source: 'm', target: 'fin' }
        ]
      )
      status, trace = run_engine(graph)

      expect(status).to eq(:success)
      expect(trace.map { |t| t[:node] }).to eq(%w[p m fin])
    end

    it 'NO da falso positivo en un ciclo A→B→A con confluencia' do
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'a', type: 'test.step' }, { id: 'b', type: 'test.step' },
          { id: 'm', type: 'logic.merge' }
        ],
        edges: [
          { source: 't', target: 'a' }, { source: 'a', target: 'b' },
          { source: 'b', target: 'a' },
          { source: 'a', target: 'm' }, { source: 'b', target: 'm' }
        ]
      )

      expect(run_engine(graph).first).to eq(:success)
    end
  end

  describe 'nodos apagados y política de error' do
    it 'salta un nodo apagado y sigue por su salida por defecto' do
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'apagado', type: 'test.step', data: { 'disabled' => true } },
          { id: 'fin', type: 'test.step' }
        ],
        edges: [{ source: 't', target: 'apagado' }, { source: 'apagado', target: 'fin' }]
      )
      status, trace = run_engine(graph)

      expect(status).to eq(:success)
      expect(trace.map { |t| t[:node] }).to eq(['fin'])
    end

    it "con onError 'continue' mata la rama pero no tumba el run" do
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'malo', type: 'test.flaky', params: { 'failAt' => [nil], 'onError' => 'continue' } },
          { id: 'despues', type: 'test.step' }
        ],
        edges: [{ source: 't', target: 'malo' }, { source: 'malo', target: 'despues' }]
      )
      status, trace = run_engine(graph)

      expect(status).to eq(:success)
      expect(trace.map { |t| t[:node] }).not_to include('despues')
    end

    it "con onError 'stop' propaga el fallo" do
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'malo', type: 'test.flaky', params: { 'failAt' => [nil] } }
        ],
        edges: [{ source: 't', target: 'malo' }]
      )

      expect { run_engine(graph) }.to raise_error(Jabvox::Flows::Engine::ExecutionError, /falló/)
    end
  end

  describe 'presupuesto de pasos' do
    it 'corta cuando el run supera el tope de pasos ejecutados' do
      items = Array.new(50) { |i| { 'n' => i } }
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'bucle', type: 'logic.loop', params: { 'items' => items } },
          { id: 'cuerpo', type: 'test.step' }
        ],
        edges: [
          { source: 't', target: 'bucle' },
          { source: 'bucle', target: 'cuerpo', sourceHandle: 'loop' }
        ]
      )

      expect { run_engine(graph, max_steps: 10) }
        .to raise_error(Jabvox::Flows::Engine::ExecutionError, /Límite de pasos ejecutados/)
    end
  end
end
