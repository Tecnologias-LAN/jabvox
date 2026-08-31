# frozen_string_literal: true

# Ayudas para construir grafos y registros de nodos en los specs del motor.
# El motor no trae nodos Jabvox en esta etapa, así que los specs registran
# handlers de prueba que dejan constancia de por dónde pasó el recorrido.
module Jabvox::FlowEngineHelpers
  # Grafo a partir de nodos/aristas escuetos: build_graph(nodes: [...], edges: [...]).
  def build_graph(nodes:, edges: [])
    Jabvox::Flows::Engine::Graph.normalize(
      'nodes' => nodes.map { |n| n.transform_keys(&:to_s) },
      'edges' => edges.each_with_index.map { |e, i| { 'id' => "e#{i}" }.merge(e.transform_keys(&:to_s)) }
    )
  end

  def build_context(trigger: {}, vars: {}, globals: {}, items_path_by_node: {})
    Jabvox::Flows::Engine::Context.new(
      account_id: 1, run_id: 'run-test', trigger: trigger, vars: vars, globals: globals,
      items_path_by_node: items_path_by_node, logger: Logger.new(File::NULL)
    )
  end

  # Registro con los tipos de prueba. `trace` recoge un registro por ejecución.
  def build_registry(trace)
    registry = Jabvox::Flows::Engine::Registry.new
    register_basic_types(registry, trace)
    register_logic_types(registry, trace)
    registry
  end

  def register_basic_types(registry, trace)
    registry.register('trigger.manual', label: 'Disparador manual')
    register_step_type(registry, trace)
    register_flaky_type(registry, trace)
    register_wait_type(registry, trace)
  end

  # Paso de ESPERA: suspende el run con el motivo y el plazo de sus params.
  def register_wait_type(registry, trace)
    registry.register('logic.delay', label: 'Esperar') do |_ctx, node, params|
      trace << { node: node.id, wait: true }
      Jabvox::Flows::Engine::NodeResult.ok(
        { 'esperando' => true },
        wait: { 'reason' => params['reason'] || 'delay', 'resumeAt' => params['resumeAt'] }
      )
    end
  end

  # Paso que solo deja constancia de que pasó, con el elemento del bucle vivo.
  def register_step_type(registry, trace)
    registry.register('test.step', label: 'Paso') do |ctx, node, params|
      trace << { node: node.id, item: ctx.loop_scope&.item, counters: ctx.loop_scope&.counters&.to_scope,
                 params: params }
      Jabvox::Flows::Engine::NodeResult.ok({ 'ok' => true, 'node' => node.id })
    end
  end

  # Paso que falla en las posiciones indicadas en `failAt`.
  def register_flaky_type(registry, trace)
    registry.register('test.flaky', label: 'Paso inestable') do |ctx, node, _params|
      position = ctx.loop_scope&.counters&.posicion
      trace << { node: node.id, item: ctx.loop_scope&.item }
      next Jabvox::Flows::Engine::NodeResult.failure("fallo en #{position}") \
        if Array(node.params['failAt']).include?(position)

      Jabvox::Flows::Engine::NodeResult.ok({ 'ok' => true })
    end
  end

  def register_logic_types(registry, trace)
    # Bucle: expone su configuración; el motor la lee para iterar.
    registry.register('logic.loop', label: 'Bucle', outputs: %w[loop done]) do |_ctx, node, params|
      trace << { node: node.id, loop: true }
      Jabvox::Flows::Engine::NodeResult.ok(params.slice('items', 'itemVar', 'batchSize', 'maxIterations',
                                                        'onItemError'))
    end
    # IF: enruta por el puerto 'true' o 'false' según la condición.
    registry.register('logic.if', label: 'Condición', outputs: %w[true false]) do |_ctx, node, params|
      trace << { node: node.id }
      matched = Jabvox::Flows::Engine::Condition.evaluate(params['left'], params['operator'], params['right'])
      Jabvox::Flows::Engine::NodeResult.ok({ 'matched' => matched }, output_port: matched ? 'true' : 'false')
    end
    # Confluencia: deja constancia de las salidas que combinó.
    registry.register('logic.merge', label: 'Confluencia') do |ctx, node, _params|
      trace << { node: node.id, merged: ctx.outputs.keys }
      Jabvox::Flows::Engine::NodeResult.ok({ 'merged' => true })
    end
  end

  # Ejecuta un grafo y devuelve [estado, traza, contexto].
  def run_engine(graph, trigger: {}, items_path_by_node: {}, max_steps: nil)
    trace = []
    ctx = build_context(trigger: trigger, items_path_by_node: items_path_by_node)
    executor = Jabvox::Flows::Engine::Executor.new(
      graph: graph, ctx: ctx, registry: build_registry(trace), max_steps: max_steps
    )
    status = executor.run(trigger_type: 'trigger.manual')
    [status, trace, ctx]
  end
end

RSpec.configure { |config| config.include Jabvox::FlowEngineHelpers }
