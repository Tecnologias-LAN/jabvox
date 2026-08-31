# frozen_string_literal: true

# Recorre la rama de un bucle para UN elemento. Vive aparte de LoopRunner porque
# es una disciplina distinta: aquí no hay tokens por arista, se avanza en
# profundidad con un `visited` POR ITERACIÓN.
class Jabvox::Flows::Engine::LoopBranchWalker
  Failure = Jabvox::Flows::Engine::LoopRunner::Failure

  def initialize(executor, graph, ctx, runner)
    @executor = executor
    @graph = graph
    @ctx = ctx
    @runner = runner
  end

  # Recorre la rama del bucle para UN elemento. nil si fue bien, o el primer
  # fallo para que el bucle aplique su política.
  #
  # `owner_loop_id`: las aristas que VUELVEN al bucle (el "y luego vuelve al
  # bucle" que el usuario dibuja para cerrar el ciclo) se ignoran como no-op. El
  # bucle ya repite solo; seguirlas lo reejecutaría hasta agotar el presupuesto.
  def run(branch_start, loop_label, owner_loop_id)
    current = branch_start.reject { |id| id == owner_loop_id }
    # El `visited` es POR ITERACIÓN: sin él, un ciclo dentro de la rama (A→B→A)
    # giraba hasta agotar el presupuesto y el run moría con "límite de pasos"
    # en vez de recorrer la rama una vez por elemento.
    visited = Set.new
    until current.empty?
      @executor.check_budget!(loop_label)
      node = @graph.node(current.shift)
      next if node.nil? || visited.include?(node.id)

      visited << node.id
      failure = step_branch(node, current, owner_loop_id)
      return failure if failure.is_a?(Failure)
    end
    nil
  end

  def step_branch(node, current, owner_loop_id)
    return skip_branch_node(node, current, owner_loop_id) if node.disabled?

    result = @executor.execute_node(node)
    @ctx.outputs[node.id] = result.output
    return branch_failure(node, result) unless result.ok?
    return wait_failure(node) if result.wait?
    return nested_loop(node, result, current, owner_loop_id) if node.loop?

    ports = @executor.outgoing_ports(node, result)
    ports.each { |port| current.concat(next_from(node.id, port, owner_loop_id)) }
    nil
  end

  def skip_branch_node(node, current, owner_loop_id)
    @executor.record_skipped_step(node)
    @ctx.outputs[node.id] = nil
    current.concat(next_from(node.id, Jabvox::Flows::Engine::Graph::DEFAULT_PORT, owner_loop_id))
    nil
  end

  # El fallo se reporta SIEMPRE al bucle, que lleva la cuenta; la política del
  # propio paso decide si además corta su rama.
  def branch_failure(node, result)
    failure = Failure.new(node_label: @executor.node_label(node), error: result.error || 'error sin detalle')
    @executor.error_policy(node) == 'stop' ? failure : nil
  end

  # Un nodo de espera dentro de un bucle NO puede suspender el run: la
  # reanudación no sabe reconstruir el estado de la iteración. Antes se trataba
  # como éxito y la espera se OMITÍA en silencio.
  def wait_failure(node)
    error = 'Los nodos de espera (esperar un tiempo > 5s, esperar hasta, esperar respuesta) no están ' \
            'soportados dentro de un bucle. Usa una espera corta (≤ 5 segundos) o saca la espera fuera del bucle.'
    # `execute_node` ya persistió el paso como `waiting` (no sabe dónde está el
    # nodo); se cierra aquí para no dejar una espera eterna en un run que no
    # está suspendido.
    @executor.recorder.resolve_waiting_step(node.id, status: :failed, error: error,
                                                     output: { 'enBucle' => true })
    Failure.new(node_label: @executor.node_label(node), error: error)
  end

  # BUCLE ANIDADO: hay que iterarlo de verdad, con su propio recorrido, y seguir
  # después por su rama 'done'. Antes caía en el recorrido plano y salía por su
  # puerto por defecto ('loop'): el cuerpo interno se ejecutaba UNA vez por
  # elemento del padre, sin iterar, y su rama 'done' nunca corría.
  def nested_loop(node, result, current, owner_loop_id)
    nested = @runner.nested_runner.run(node, result)
    @ctx.outputs[node.id] = (result.output.is_a?(Hash) ? result.output : {}).merge('resumen' => nested)
    current.concat(next_from(node.id, 'done', owner_loop_id))
    nil
  end

  def next_from(node_id, port, owner_loop_id)
    @graph.successors(node_id, port).reject { |id| id == owner_loop_id }
  end
end
