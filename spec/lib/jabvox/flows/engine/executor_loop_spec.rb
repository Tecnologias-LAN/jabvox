# frozen_string_literal: true

require 'rails_helper'

# Casos de bucle que YA fallaron en la versión TypeScript. Cada uno fija una
# garantía concreta del recorrido, no un detalle de implementación.
RSpec.describe Jabvox::Flows::Engine::Executor do
  # Bucle simple: disparador → bucle, rama 'loop' → paso, rama 'done' → cierre.
  def loop_graph(items, batch_size: 1, on_item_error: 'stop', body_type: 'test.step', body_params: {})
    build_graph(
      nodes: [
        { id: 't', type: 'trigger.manual' },
        { id: 'bucle', type: 'logic.loop',
          params: { 'items' => items, 'batchSize' => batch_size, 'onItemError' => on_item_error } },
        { id: 'cuerpo', type: body_type, params: body_params },
        { id: 'fin', type: 'test.step' }
      ],
      edges: [
        { source: 't', target: 'bucle' },
        { source: 'bucle', target: 'cuerpo', sourceHandle: 'loop' },
        { source: 'bucle', target: 'fin', sourceHandle: 'done' }
      ]
    )
  end

  describe 'iteración por elementos' do
    [0, 1, 3, 20, 200].each do |size|
      it "recorre #{size} elemento(s) ejecutando el cuerpo exactamente #{size} vez/veces" do
        items = Array.new(size) { |i| { 'n' => i } }
        status, trace = run_engine(loop_graph(items))

        body_runs = trace.select { |t| t[:node] == 'cuerpo' }
        expect(status).to eq(:success)
        expect(body_runs.length).to eq(size)
        # Cada iteración ve SU elemento, en orden.
        expect(body_runs.map { |t| t[:item] }).to eq(items)
      end
    end

    it 'numera los contadores del bucle en base 1 y con los totales correctos' do
      _status, trace = run_engine(loop_graph([{ 'n' => 0 }, { 'n' => 1 }, { 'n' => 2 }]))

      counters = trace.select { |t| t[:node] == 'cuerpo' }.map { |t| t[:counters] }
      expect(counters.map { |c| c['posicion'] }).to eq([1, 2, 3])
      expect(counters.map { |c| c['iteracion'] }).to eq([1, 2, 3])
      expect(counters.map { |c| c['totalElementos'] }.uniq).to eq([3])
    end

    it 'agrupa por lotes respetando batchSize' do
      items = Array.new(5) { |i| { 'n' => i } }
      _status, trace = run_engine(loop_graph(items, batch_size: 2))

      counters = trace.select { |t| t[:node] == 'cuerpo' }.map { |t| t[:counters] }
      # 5 elementos en lotes de 2 → 3 iteraciones, posición absoluta continua.
      expect(counters.map { |c| c['iteracion'] }).to eq([1, 1, 2, 2, 3])
      expect(counters.map { |c| c['posicionEnLote'] }).to eq([1, 2, 1, 2, 1])
      expect(counters.map { |c| c['posicion'] }).to eq([1, 2, 3, 4, 5])
    end
  end

  describe "rama 'done'" do
    it 'se ejecuta SIEMPRE y DESPUÉS de todas las iteraciones' do
      items = Array.new(3) { |i| { 'n' => i } }
      _status, trace = run_engine(loop_graph(items))

      order = trace.map { |t| t[:node] }
      expect(order.count('fin')).to eq(1)
      # El cierre va después de la última vuelta del cuerpo.
      expect(order.rindex('cuerpo')).to be < order.index('fin')
    end

    it 'se ejecuta aunque la colección esté vacía' do
      status, trace = run_engine(loop_graph([]))

      expect(status).to eq(:success)
      expect(trace.map { |t| t[:node] }).to include('fin')
      expect(trace.select { |t| t[:node] == 'cuerpo' }).to be_empty
    end

    it 'publica el resumen del recorrido en la salida del bucle' do
      _status, _trace, ctx = run_engine(loop_graph(Array.new(3) { |i| { 'n' => i } }))

      resumen = ctx.outputs['bucle']['resumen']
      expect(resumen['elementosProcesados']).to eq(3)
      expect(resumen['totalElementos']).to eq(3)
      expect(resumen['elementosConError']).to eq(0)
    end
  end

  describe 'bucle anidado' do
    it 'produce 5 x 4 = 20 pares únicos' do
      externos = Array.new(5) { |i| { 'ext' => i } }
      internos = Array.new(4) { |i| { 'int' => i } }
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'externo', type: 'logic.loop', params: { 'items' => externos, 'itemVar' => 'ext' } },
          { id: 'interno', type: 'logic.loop', params: { 'items' => internos, 'itemVar' => 'int' } },
          # El elemento del bucle EXTERNO se lee por `{{vars.<itemVar>}}`: el
          # alcance `{{item.*}}` publica solo el bucle más interno.
          { id: 'cuerpo', type: 'test.step', params: { 'par' => '{{vars.ext.ext}}-{{item.int}}' } },
          { id: 'fin', type: 'test.step' }
        ],
        edges: [
          { source: 't', target: 'externo' },
          { source: 'externo', target: 'interno', sourceHandle: 'loop' },
          { source: 'interno', target: 'cuerpo', sourceHandle: 'loop' },
          { source: 'externo', target: 'fin', sourceHandle: 'done' }
        ]
      )
      status, trace = run_engine(graph)

      pares = trace.select { |t| t[:node] == 'cuerpo' }.map { |t| t[:params]['par'] }
      expect(status).to eq(:success)
      expect(pares.length).to eq(20)
      expect(pares.uniq.length).to eq(20)
    end
  end

  describe 'arista de retorno de la rama al propio bucle' do
    it 'NO impide que el bucle se ejecute' do
      items = Array.new(3) { |i| { 'n' => i } }
      graph = build_graph(
        nodes: [
          { id: 't', type: 'trigger.manual' },
          { id: 'previo', type: 'test.step' },
          { id: 'bucle', type: 'logic.loop', params: { 'items' => items } },
          { id: 'cuerpo', type: 'test.step' },
          { id: 'fin', type: 'test.step' }
        ],
        edges: [
          { source: 't', target: 'previo' },
          { source: 'previo', target: 'bucle' },
          { source: 'bucle', target: 'cuerpo', sourceHandle: 'loop' },
          # El usuario dibuja "y luego vuelve al bucle": es el cierre del ciclo.
          { source: 'cuerpo', target: 'bucle' },
          { source: 'bucle', target: 'fin', sourceHandle: 'done' }
        ]
      )
      status, trace = run_engine(graph)

      expect(status).to eq(:success)
      # El bucle corre, el cuerpo itera 3 veces y la rama 'done' cierra.
      expect(trace.count { |t| t[:node] == 'cuerpo' }).to eq(3)
      expect(trace.map { |t| t[:node] }).to include('fin')
    end
  end

  describe 'política ante fallo de un elemento' do
    it "con onItemError 'continue' procesa 199 de 200 y marca 1 fallido" do
      items = Array.new(200) { |i| { 'n' => i } }
      graph = loop_graph(items, on_item_error: 'continue', body_type: 'test.flaky',
                                body_params: { 'failAt' => [3] })
      status, _trace, ctx = run_engine(graph)

      resumen = ctx.outputs['bucle']['resumen']
      expect(status).to eq(:success)
      expect(resumen['elementosProcesados']).to eq(199)
      expect(resumen['elementosConError']).to eq(1)
      expect(resumen['errores'].first['posicion']).to eq(3)
    end

    it "con onItemError 'stop' detiene el run en el elemento que falla" do
      items = Array.new(10) { |i| { 'n' => i } }
      graph = loop_graph(items, on_item_error: 'stop', body_type: 'test.flaky',
                                body_params: { 'failAt' => [3] })

      expect { run_engine(graph) }
        .to raise_error(Jabvox::Flows::Engine::ExecutionError, /se detuvo en el elemento 3 de 10/)
    end
  end
end
