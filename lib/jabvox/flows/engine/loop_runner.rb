# frozen_string_literal: true

# Recorrido de `logic.loop`: iteración por lotes, política ante fallo de un
# elemento y bucles ANIDADOS. Publica `{{item.*}}` y `{{bucle.*}}` en cada vuelta
# y devuelve el resumen que lee la rama 'done'.
class Jabvox::Flows::Engine::LoopRunner
  Failure = Struct.new(:node_label, :error, keyword_init: true)

  # Estado vivo de UN recorrido del bucle: agrupa lo que todas las fases de la
  # iteración necesitan, para no ir pasando ocho parámetros sueltos.
  State = Struct.new(:loop_node, :label, :branch_start, :config, :summary, :position,
                     keyword_init: true) do
    def items
      config[:items]
    end

    def total_batches
      config[:batches].length
    end
  end

  def initialize(executor, graph, ctx, budget)
    @executor = executor
    @graph = graph
    @ctx = ctx
    @budget = budget
  end

  def run(loop_node, loop_result)
    config = read_config(loop_result)
    summary = new_summary(config)
    # Un bucle anidado debe devolver el alcance del padre al terminar, no dejar
    # el suyo colgando.
    previous_scope = @ctx.loop_scope
    begin
      iterate(loop_node, config, summary)
    ensure
      @ctx.loop_scope = previous_scope
    end
    finish(summary, loop_node)
  end

  # Runner para un bucle ANIDADO: comparte el MISMO presupuesto de pasos, así el
  # tope es de verdad un tope del run completo y no por nivel de anidamiento.
  def nested_runner
    self.class.new(@executor, @graph, @ctx, @budget)
  end

  private

  # Recorrido de la rama, extraído para que el bucle se ocupe solo de iterar.
  def branch_walker
    @branch_walker ||= Jabvox::Flows::Engine::LoopBranchWalker.new(@executor, @graph, @ctx, self)
  end

  def read_config(loop_result)
    out = loop_result.output.is_a?(Hash) ? loop_result.output : {}
    items = out['items'].is_a?(Array) ? out['items'] : []
    batch_size = Jabvox::Flows::Engine::LoopLimits.batch_size(out['batchSize'])
    { items: items, item_var: out['itemVar'].presence || 'item', batch_size: batch_size,
      max_iterations: Jabvox::Flows::Engine::LoopLimits.max_iterations(out['maxIterations']),
      on_item_error: out['onItemError'] == 'continue' ? 'continue' : 'stop',
      batches: Jabvox::Flows::Engine::LoopLimits.chunk(items, batch_size) }
  end

  def new_summary(config)
    { iteraciones: 0, elementosProcesados: 0, elementosConError: 0,
      totalElementos: config[:items].length, totalIteraciones: config[:batches].length,
      tamanoLote: config[:batch_size], errores: [], detenidoPor: nil,
      correctos: [], fallidos: [], informe: '', fallos_detalle: [] }
  end

  def iterate(loop_node, config, summary)
    state = State.new(
      loop_node: loop_node, label: @executor.node_label(loop_node),
      # Un bucle conectado a SÍ MISMO por 'loop' no arranca rama: ya repite solo.
      branch_start: @graph.successors(loop_node.id, 'loop').reject { |id| id == loop_node.id },
      config: config, summary: summary, position: 0
    )

    config[:batches].each_with_index do |batch, iteration|
      guard_iteration(state.label, iteration, batch, config)
      summary[:iteraciones] += 1
      run_batch(state, batch, iteration)
    end
  end

  def guard_iteration(label, iteration, batch, config)
    # TOPE DE ITERACIONES: cota del recorrido real, no solo del plan del handler.
    if iteration >= config[:max_iterations]
      raise Jabvox::Flows::Engine::ExecutionError,
            "El bucle «#{label}» alcanzó el límite de #{config[:max_iterations]} iteraciones y se detuvo para no " \
            'girar sin fin. Sube el "Límite de iteraciones", aumenta el "Tamaño de lote" o reduce la colección.'
    end
    # BUCLE SIN AVANCE: un lote vacío no consume elementos, seguir no acerca el final.
    return unless batch.empty?

    raise Jabvox::Flows::Engine::ExecutionError,
          "El bucle «#{label}» no avanzó: la iteración #{iteration + 1} no consumió ningún elemento. " \
          'Revisa la "Colección de elementos" y el "Tamaño de lote".'
  end

  def run_batch(state, batch, iteration)
    batch.each_with_index do |item, in_batch|
      state.position += 1
      publish_scope(state, item, batch, iteration, in_batch)
      failure = branch_walker.run(state.branch_start, state.label, state.loop_node.id)
      record_item(state, failure, item, iteration)
    end
  end

  # Alcance del elemento: habilita `{{item.*}}` y `{{bucle.*}}`. Se sigue
  # escribiendo en ctx.vars por compatibilidad con los flujos guardados que leen
  # `{{vars.<itemVar>.*}}`, la única vía que funcionaba antes.
  def publish_scope(state, item, batch, iteration, in_batch)
    config = state.config
    counters = Jabvox::Flows::Engine::Context::LoopCounters.new(
      iteracion: iteration + 1, posicion_en_lote: in_batch + 1, posicion: state.position,
      total_elementos: state.items.length, total_iteraciones: state.total_batches,
      tamano_lote: config[:batch_size], lote: batch
    )
    @ctx.loop_scope = Jabvox::Flows::Engine::Context::LoopScope.new(
      item: item, item_var: config[:item_var], counters: counters,
      loop_id: state.loop_node.id, loop_label: state.label
    )
    @ctx.vars[config[:item_var]] = item
  end

  def record_item(state, failure, item, iteration)
    summary = state.summary
    identity = Jabvox::Flows::Engine::LoopReport.identify(item)
    return record_success(identity, summary) if failure.nil?

    record_failure(failure, identity, state.position, iteration, summary)
    return if state.config[:on_item_error] == 'continue'

    summary[:detenidoPor] = "elemento #{state.position}: #{failure.error}"
    raise Jabvox::Flows::Engine::ExecutionError, stopped_message(state, failure, iteration)
  end

  def stopped_message(state, failure, iteration)
    "El bucle «#{state.label}» se detuvo en el elemento #{state.position} de #{state.items.length} " \
      "(iteración #{iteration + 1} de #{state.total_batches}), en «#{failure.node_label}»: #{failure.error}"
  end

  def record_success(identity, summary)
    summary[:elementosProcesados] += 1
    summary[:correctos] << identity[:etiqueta]
  end

  def record_failure(failure, identity, position, iteration, summary)
    summary[:elementosConError] += 1
    summary[:fallidos] << identity[:etiqueta]
    summary[:fallos_detalle] << { etiqueta: identity[:etiqueta], error: failure.error }
    error = { posicion: position, iteracion: iteration + 1, paso: failure.node_label,
              error: failure.error, elemento: identity[:etiqueta] }
    %i[contactoId leadId conversacionId].each { |k| error[k] = identity[k] unless identity[k].nil? }
    summary[:errores] << error
  end

  def finish(summary, loop_node)
    detalle = summary.delete(:fallos_detalle)
    summary[:informe] = Jabvox::Flows::Engine::LoopReport.build_text(
      procesados: summary[:elementosProcesados], con_error: summary[:elementosConError],
      total: summary[:totalElementos], correctos: summary[:correctos], fallidos: detalle
    )
    log_errors(summary, loop_node)
    summary.deep_stringify_keys
  end

  def log_errors(summary, loop_node)
    return unless summary[:elementosConError].positive?

    @ctx.logger.warn(
      "Bucle «#{@executor.node_label(loop_node)}»: #{summary[:elementosProcesados]} elemento(s) procesados " \
      "y #{summary[:elementosConError]} con error de #{summary[:totalElementos]}."
    )
  end
end
