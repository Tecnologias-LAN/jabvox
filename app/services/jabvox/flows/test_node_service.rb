# frozen_string_literal: true

# PROBAR UN PASO: ejecuta UN nodo suelto y devuelve su salida de forma síncrona,
# sin recorrer el resto del grafo.
#
# La prueba se registra como una ejecución marcada `isTest`, así queda su traza
# consultable, pero se excluye de las métricas de producción.
class Jabvox::Flows::TestNodeService
  Contract = Jabvox::Flows::Engine::NodeOutput

  # `context` agrupa de dónde salen los datos de la prueba: el disparo simulado,
  # las salidas ya probadas en el editor y si se precarga el último run.
  def initialize(flow:, version:, node_id:, user:, context: {})
    @flow = flow
    @version = version
    @node_id = node_id.to_s
    @user = user
    @payload = context[:payload] || {}
    @prior_outputs = context[:prior_outputs] || {}
    @use_last_run_context = context.fetch(:use_last_run_context, true)
  end

  def call
    graph = @version.engine_graph
    node = graph.nodes.find { |n| n.id == @node_id }
    return not_found if node.nil?

    loop_owner = enclosing_loop(graph, node)
    return blocked_by_loop(node, loop_owner) if loop_owner

    execute(graph, node)
  end

  private

  def registry
    @registry ||= Jabvox::Flows::Registry.build
  end

  # Un paso DENTRO de un bucle no se puede probar suelto: `{{item.*}}` no tiene
  # valor mientras el bucle no itere. Se dice, en vez de devolver un falso "ok".
  def blocked_by_loop(node, loop_node)
    label = label_of(loop_node)
    result(node, status: 'failed', duration_ms: 0,
                 error: "Este paso está dentro del bucle «#{label}», así que {{item.…}} no tiene " \
                        'valor todavía. Ejecuta el flujo (o «Ejecutar desde aquí» en el bucle) ' \
                        'para probarlo con datos reales.')
      .merge('loopContext' => { 'nodeId' => loop_node.id, 'label' => label })
  end

  def execute(graph, node)
    run = create_run
    ctx = build_context(graph, run)
    seeded = seed_outputs(ctx, graph, node)
    missing = missing_outputs(ctx, node)
    return stop_missing(run, node, missing, seeded) if missing.any?

    started = Time.current
    outcome = run_single(graph, ctx, node, run)
    finish(run, outcome)
    payload_of(node, outcome, started, run, seeded)
  end

  # Se ejecuta con el MISMO executor que una ejecución real: probar un paso y
  # ejecutarlo de verdad no pueden divergir.
  def run_single(graph, ctx, node, run)
    executor = Jabvox::Flows::Engine::Executor.new(
      graph: graph, ctx: ctx, registry: registry,
      recorder: Jabvox::Flows::Engine::ActiveRecordRecorder.new(run)
    )
    executor.execute_node(node)
  end

  def create_run
    JabvoxFlowRun.create!(
      account_id: @flow.account_id, flow: @flow, version: @version, status: :running,
      started_at: Time.current, triggered_by: @user&.id,
      trigger: @payload.merge('type' => 'trigger.__test', 'isTest' => true,
                              'testNodeId' => @node_id)
    )
  end

  def build_context(graph, run)
    variables = JabvoxFlowAccountVariable.where(account_id: @flow.account_id).to_a
    Jabvox::Flows::Engine::Context.new(
      account_id: @flow.account_id, run_id: run.id, trigger: @payload,
      globals: variables.index_by(&:key).transform_values(&:value),
      secret_values: variables.select(&:secret).filter_map { |v| v.value.presence },
      items_path_by_node: items_paths(graph), logger: Rails.logger
    )
  end

  def items_paths(graph)
    graph.nodes.each_with_object({}) do |node, map|
      path = registry.items_path(node.type)
      map[node.id] = path unless path.nil?
    end
  end

  # Salidas disponibles para las referencias del nodo: las del último run y las
  # de los pasos ya probados en el editor, que tienen PRIORIDAD por ser lo más
  # reciente que el usuario ha visto.
  def seed_outputs(ctx, graph, node)
    referenced = referenced_nodes(node)
    from_run = @use_last_run_context ? last_run_outputs(graph) : {}
    from_run.each { |id, value| ctx.outputs[id] = value if referenced.include?(id) }
    @prior_outputs.each { |id, value| ctx.outputs[id] = value if referenced.include?(id.to_s) }
    ctx.outputs.keys
  end

  def last_run_outputs(_graph)
    run = @flow.runs.where(status: [:success, :failed]).order(created_at: :desc).first
    return {} if run.nil?

    run.steps.where(status: :success).order(:id).each_with_object({}) do |step, acc|
      acc[step.node_id] = step.output
    end
  end

  # Ids citados en las expresiones `{{node.<id>...}}` de los params del nodo.
  def referenced_nodes(node)
    node.params.to_json.scan(/\{\{\s*node\.([A-Za-z0-9_\-]+)/).flatten.uniq
  end

  # Referencias sin dato: la prueba se DETIENE en vez de devolver un "correcto"
  # calculado sobre huecos vacíos.
  def missing_outputs(ctx, node)
    referenced_nodes(node).reject { |id| ctx.outputs.key?(id) }
  end

  def stop_missing(run, node, missing, seeded)
    run.update!(status: :failed, finished_at: Time.current)
    result(node, status: 'failed', duration_ms: 0, meta: { run_id: run.id, seeded: seeded },
                 error: 'Faltan datos de pasos anteriores: ' \
                        "#{missing.join(', ')}. Pruébalos primero (o ejecuta el flujo) para " \
                        'que esta prueba tenga con qué trabajar.')
      .merge('missingOutputs' => missing)
  end

  def finish(run, outcome)
    run.update!(status: outcome.ok? ? :success : :failed, finished_at: Time.current,
                error: outcome.ok? ? nil : outcome.error)
  end

  def payload_of(node, outcome, started, run, seeded)
    duration = ((Time.current - started) * 1000).round
    base = result(node, status: outcome.ok? ? 'success' : 'failed', duration_ms: duration,
                        meta: { run_id: run.id, seeded: seeded },
                        error: outcome.ok? ? nil : outcome.error)
    return base unless outcome.ok?

    base.merge('output' => outcome.output,
               'outputContract' => Contract.reference_contract(
                 outcome.output, registry.items_path(node.type)
               ).deep_stringify_keys)
  end

  def result(node, status:, duration_ms:, error: nil, meta: {})
    { 'nodeId' => node.id, 'nodeType' => node.type, 'status' => status,
      'durationMs' => duration_ms, 'disabled' => disabled?(node),
      'contextRunId' => nil, 'runId' => meta[:run_id]&.to_s, 'error' => error,
      'seededOutputs' => meta[:seeded] || [] }.compact
  end

  def disabled?(node)
    node.data.is_a?(Hash) && node.data['disabled'] == true
  end

  # Bucle que ENCIERRA al nodo: se sigue hacia atrás desde el puerto 'loop'.
  def enclosing_loop(graph, node)
    graph.nodes.select { |n| n.type == 'logic.loop' }.find do |loop_node|
      reachable_from_loop(graph, loop_node).include?(node.id)
    end
  end

  # Recorrido de la RAMA del bucle. Se para al volver al propio bucle: la arista
  # de vuelta es redundante y seguirla giraría en redondo.
  def reachable_from_loop(graph, loop_node)
    seen = Set.new
    queue = graph.successors(loop_node.id, 'loop').dup
    until queue.empty?
      current = queue.shift
      next if current == loop_node.id || !seen.add?(current)

      queue.concat(graph.outgoing(current).map(&:target))
    end
    seen
  end

  def label_of(node)
    custom = node.data.is_a?(Hash) ? node.data['label'] : nil
    return custom if custom.is_a?(String) && custom.strip != ''

    registry.label(node.type) || node.type
  end

  def not_found
    { 'error' => 'El paso no existe en la versión guardada del flujo.' }
  end
end
