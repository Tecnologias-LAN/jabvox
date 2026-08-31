# frozen_string_literal: true

# MOTOR DE RECORRIDO. Ejecuta un grafo con el modelo de TOKENS POR ARISTA
# (ver TokenRouter), delega los bucles en LoopRunner y falla cerrado ante una
# parada silenciosa. No conoce ningún nodo Jabvox: los tipos llegan por Registry.
class Jabvox::Flows::Engine::Executor
  # Presupuesto de pasos por run. Con los `visited` de ambos recorridos los
  # ciclos ya no giran en infinito, así que el tope protege contra VOLUMEN
  # desbocado: cubre el tope duro del bucle con margen para el resto del grafo.
  DEFAULT_MAX_STEPS = 12_000

  attr_reader :ctx, :graph, :recorder
  # Nodo que suspendió el run y su descriptor de espera (nil si no se suspendió).
  attr_reader :waiting_node, :wait_descriptor

  def initialize(graph:, ctx:, registry:, recorder: nil, max_steps: nil)
    @graph = graph
    @ctx = ctx
    @registry = registry
    @recorder = recorder || Jabvox::Flows::Engine::NullRecorder.new
    @max_steps = max_steps || DEFAULT_MAX_STEPS
    @budget = { executed: 0 }
  end

  # Recorre el grafo. `trigger_type` selecciona las raíces; `start_nodes` las
  # impone (reanudación de un run en espera, o "ejecutar desde aquí").
  # Devuelve :success o :waiting; lanza ExecutionError ante fallo.
  def run(trigger_type: nil, start_nodes: nil, trigger_match: nil, any_trigger_type: false)
    roots, fired_triggers = resolve_roots(trigger_type, start_nodes, trigger_match, any_trigger_type)
    @analysis = Jabvox::Flows::Engine::GraphAnalysis.new(@graph, roots)
    @router = Jabvox::Flows::Engine::TokenRouter.new(@graph, @analysis)
    seed(start_nodes, fired_triggers)

    waiting = drain_queue
    return :waiting if waiting

    assert_no_stall!
    :success
  end

  def steps_executed
    @budget[:executed]
  end

  # Nombre legible de un paso para los mensajes del motor.
  def node_label(node)
    params = node.params.is_a?(Hash) ? node.params : {}
    custom = params['label']
    return custom.strip if custom.is_a?(String) && custom.strip != ''

    @registry.label(node.type) || node.type
  end

  # Política ante error de un nodo.
  def error_policy(node)
    params = node.params.is_a?(Hash) ? node.params : {}
    params['onError'] == 'continue' ? 'continue' : 'stop'
  end

  # Puertos de salida a seguir tras ejecutar un nodo.
  def outgoing_ports(node, result)
    return [result.output_port] if result.output_port.present?

    [@registry.default_port(node.type)]
  end

  def check_budget!(context_label = nil)
    return if @budget[:executed] < @max_steps

    detail = context_label ? " dentro del bucle «#{context_label}»" : ''
    raise Jabvox::Flows::Engine::ExecutionError,
          "Límite de pasos ejecutados alcanzado (#{@max_steps})#{detail}. " \
          'Puede que el flujo se esté repitiendo sin fin, o que la colección de entrada sea demasiado grande.'
  end

  # Ejecuta un nodo y persiste su paso, sellando la iteración del bucle si la hay.
  def execute_node(node)
    step = @recorder.start_step(node: node, ctx: @ctx, loop_context: step_loop_context)
    @budget[:executed] += 1
    result = invoke_handler(node)
    @recorder.finish_step(step, result: result, ctx: @ctx)
    result
  end

  # Deja traza de un nodo APAGADO que el motor saltó.
  def record_skipped_step(node)
    @recorder.skipped_step(node: node, ctx: @ctx, loop_context: step_loop_context)
  end

  private

  def invoke_handler(node)
    handler = @registry.handler(node.type)
    return missing_handler(node) if handler.nil?

    params = Jabvox::Flows::Engine::Template.resolve(node.params, @ctx)
    result = handler.call(@ctx, node, params)
    result.is_a?(Jabvox::Flows::Engine::NodeResult) ? result : Jabvox::Flows::Engine::NodeResult.ok(result)
  rescue StandardError => e
    Jabvox::Flows::Engine::NodeResult.failure(e.message)
  end

  def missing_handler(node)
    message = if node.type.present?
                "No hay handler para el tipo '#{node.type}'."
              else
                "El nodo '#{node.id}' no tiene tipo (falta data.nodeType en el grafo guardado); " \
                  'revísalo en el editor y vuelve a guardarlo.'
              end
    Jabvox::Flows::Engine::NodeResult.failure(message)
  end

  # Contexto de iteración a sellar. En bucles ANIDADOS gana el más interno:
  # `ctx.loop_scope` es el alcance vivo, que es el que corresponde.
  def step_loop_context
    scope = @ctx.loop_scope
    return nil if scope.nil? || scope.loop_id.nil?

    Jabvox::Flows::Engine::StepIteration.context_of(scope.loop_id, scope.loop_label, scope.counters)
  end

  def resolve_roots(trigger_type, start_nodes, trigger_match, any_trigger_type)
    return [start_nodes, []] if start_nodes

    fired = find_triggers(trigger_type, trigger_match, any_trigger_type)
    raise Jabvox::Flows::Engine::ExecutionError, no_trigger_message(trigger_type, any_trigger_type) if fired.empty?

    [fired.map(&:id), fired]
  end

  # Un trigger APAGADO no dispara nunca. `any_trigger_type` es la prueba manual
  # del flujo completo: la restricción real es entonces el matcher por nodeId.
  def find_triggers(trigger_type, trigger_match, any_trigger_type)
    @graph.nodes.select do |node|
      matches = any_trigger_type ? node.type.start_with?('trigger.') : node.type == trigger_type
      next false unless matches
      next false if node.disabled?

      trigger_match.nil? || trigger_match.call(node)
    end
  end

  def no_trigger_message(trigger_type, any_trigger_type)
    return 'El flujo no tiene ningún disparador activo que ejecutar.' if any_trigger_type

    "No hay nodo trigger de tipo '#{trigger_type}' activo en el grafo."
  end

  def seed(start_nodes, fired_triggers)
    # run-from / reanudación: los nodos de arranque se ejecutan directamente.
    return @router.seed(start_nodes) if start_nodes

    fired_triggers.each do |trigger|
      # El trigger no tiene handler: sembramos su salida y disparamos aristas.
      @ctx.outputs[trigger.id] = @ctx.trigger
      @router.mark_visited(trigger.id)
      @router.resolve_outgoing(trigger.id, Set[Jabvox::Flows::Engine::Graph::DEFAULT_PORT])
    end
  end

  def drain_queue
    while @router.pending?
      check_budget!
      node = @graph.node(@router.next_node)
      next if node.nil?
      # Con el modelo de tokens un nodo entra en la cola una sola vez; esto solo
      # protege contra siembras duplicadas (start_nodes repetidos).
      next if @router.visited?(node.id)

      @router.mark_visited(node.id)
      return true if process_node(node) == :waiting
    end
    false
  end

  def process_node(node)
    return skip_node(node) if node.disabled?

    result = execute_node(node)
    @ctx.outputs[node.id] = result.output
    return suspend(node, result) if result.wait?

    return fail_or_continue(node, result) unless result.ok?

    advance(node, result)
  end

  # Nodo de espera: el recorrido para aquí y deja el PUNTERO DE REANUDACIÓN
  # (nodo + descriptor) para que la frontera con la BD lo persista.
  def suspend(node, result)
    @waiting_node = node
    @wait_descriptor = Jabvox::Flows::Engine::WaitDescriptor.normalize(result.wait)
    :waiting
  end

  # Nodo APAGADO: no se ejecuta su handler, pero el flujo NO se corta — se
  # continúa por la salida por defecto 'out' como si hubiera pasado.
  def skip_node(node)
    record_skipped_step(node)
    @ctx.outputs[node.id] = nil
    @router.resolve_outgoing(node.id, Set[Jabvox::Flows::Engine::Graph::DEFAULT_PORT])
    nil
  end

  def fail_or_continue(node, result)
    if error_policy(node) == 'stop'
      raise Jabvox::Flows::Engine::ExecutionError,
            "Nodo '#{node.type}' (#{node.id}) falló: #{result.error}"
    end
    # continue: sus salidas se resuelven MUERTAS, así un merge aguas abajo no se
    # queda esperando esta rama.
    @router.resolve_outgoing(node.id, nil)
    nil
  end

  def advance(node, result)
    return run_loop(node, result) if node.loop?

    @router.resolve_outgoing(node.id, Set.new(outgoing_ports(node, result)))
    nil
  end

  # Recorre la rama 'loop' por lotes y añade el RESUMEN a la salida, que es lo
  # que la rama 'done' y la interfaz leen para el informe final.
  def run_loop(node, result)
    summary = Jabvox::Flows::Engine::LoopRunner.new(self, @graph, @ctx, @budget).run(node, result)
    base = result.output.is_a?(Hash) ? result.output : {}
    @ctx.outputs[node.id] = base.merge('resumen' => summary)
    @router.resolve_outgoing(node.id, Set['done'])
    nil
  end

  # FALLAR CERRADO ante una parada silenciosa.
  #
  # La cola se vació, así que el recorrido terminó. Si queda algún nodo
  # ALCANZABLE que ni se ejecutó, ni se saltó por estar apagado, ni murió por una
  # rama no tomada, el modelo de tokens lo dejó bloqueado: sus entradas nunca se
  # completaron. Eso NO es un final legítimo, y antes se devolvía `success` como
  # si nada (el bucle con el ciclo cerrado terminaba "correcto" habiendo
  # ejecutado solo el paso anterior al bucle).
  #
  # Se excluyen el interior de los bucles (lo recorre LoopRunner, no pasa por
  # `visited`) y los nodos sin ninguna arista contada entrante, que son
  # huérfanos de verdad y nunca se pretendió ejecutar.
  def assert_no_stall!
    stalled = @analysis.reachable.select do |id|
      !@router.visited?(id) && @router.dead_nodes.exclude?(id) &&
        @analysis.loop_internal.exclude?(id) &&
        @analysis.counted_incoming.include?(id) && @graph.node?(id)
    end
    return if stalled.empty?

    raise Jabvox::Flows::Engine::ExecutionError, stall_message(stalled)
  end

  def stall_message(stalled)
    names = stalled.first(5).map { |id| "«#{node_label(@graph.node(id))}»" }.join(', ')
    rest = stalled.length > 5 ? " y #{stalled.length - 5} paso(s) más" : ''
    @ctx.logger.error("El flujo se detuvo sin ejecutar #{stalled.length} paso(s) conectados: #{stalled.join(', ')}.")
    "El flujo terminó dejando #{stalled.length} paso(s) sin ejecutar aunque estaban conectados: " \
      "#{names}#{rest}. Suele indicar una conexión que el motor no puede resolver (por ejemplo una " \
      'confluencia que espera una rama que nunca llega). Revisa las conexiones de esos pasos.'
  end
end
