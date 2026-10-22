# frozen_string_literal: true

# Arranca (o reanuda) un run y persiste su desenlace. Es la frontera entre el
# motor —que no sabe nada de ActiveRecord— y la base de datos.
class Jabvox::Flows::RunService
  def initialize(run, registry: nil)
    @run = run
    @registry = registry || Jabvox::Flows::Registry.build
  end

  # Ejecuta el run completo. Devuelve el estado final persistido.
  #
  # `trigger_node_id` fija el disparador concreto a sembrar: un flujo puede tener
  # varios triggers del mismo tipo (p. ej. dos `jabvox_event` con filtros distintos)
  # y solo debe arrancar el que coincidió con el evento.
  def call(trigger_type: 'trigger.manual', start_nodes: nil, trigger_node_id: nil)
    @run.update!(status: :running, started_at: Time.current)
    executor = build_executor(build_context)
    trigger_match = trigger_node_id.present? ? ->(node) { node.id.to_s == trigger_node_id.to_s } : nil
    finish(executor.run(trigger_type: trigger_type, start_nodes: start_nodes, trigger_match: trigger_match), executor)
  rescue Jabvox::Flows::Engine::ExecutionError, StandardError => e
    @run.update!(status: :failed, error: e.message, finished_at: Time.current)
    :failed
  end

  # REANUDA un run suspendido continuando por los SUCESORES del nodo de espera.
  #
  # `payload` es la respuesta que lo despierta: queda visible como `{{vars.resume}}`
  # y como salida del propio nodo de espera, que es donde el usuario la busca.
  # `timed_out` significa "venció el plazo sin respuesta", y eso SOLO es un fallo
  # para `wait_response`: para `delay`/`wait_until` el vencimiento ES el evento
  # esperado y el run continúa con normalidad.
  def resume(payload: {}, timed_out: false)
    return :not_waiting unless claim_for_resume

    node_id = @run.waiting_node_id
    return missing_pointer if node_id.blank?
    return fail_by_timeout(node_id) if timed_out && wait_response?

    continue_from(node_id, payload || {}, timed_out)
  rescue Jabvox::Flows::Engine::ExecutionError, StandardError => e
    @run.update!(status: :failed, error: e.message, finished_at: Time.current)
    :failed
  end

  private

  def build_executor(ctx)
    Jabvox::Flows::Engine::Executor.new(
      graph: @run.version.engine_graph, ctx: ctx, registry: @registry, recorder: recorder
    )
  end

  def recorder
    @recorder ||= Jabvox::Flows::Engine::ActiveRecordRecorder.new(@run)
  end

  def build_context(vars: {}, outputs: {}, trigger: nil)
    graph = @run.version.engine_graph
    ctx = Jabvox::Flows::Engine::Context.new(
      account_id: @run.account_id, run_id: @run.id, trigger: trigger || @run.trigger || {},
      vars: vars, globals: globals, secret_values: secret_values,
      items_path_by_node: items_path_by_node(graph), logger: Rails.logger
    )
    outputs.each { |id, value| ctx.outputs[id] = value }
    ctx
  end

  # Las variables globales se cargan UNA sola vez al arrancar, nunca por nodo.
  def variables
    @variables ||= JabvoxFlowAccountVariable.where(account_id: @run.account_id).to_a
  end

  def globals
    variables.index_by(&:key).transform_values(&:value)
  end

  # Valores en claro de las secretas: el motor los usa para redactarlos en la traza.
  def secret_values
    variables.select(&:secret).map(&:value).compact_blank
  end

  def items_path_by_node(graph)
    graph.nodes.each_with_object({}) do |node, map|
      path = @registry.items_path(node.type)
      map[node.id] = path unless path.nil?
    end
  end

  def finish(status, executor)
    return suspend!(executor) if status == :waiting

    @run.update!(status: :success, finished_at: Time.current)
    :success
  end

  # Un run suspendido NO ha terminado: conserva el puntero de reanudación y no
  # se le pone `finished_at` (lo hará quien lo reanude).
  def suspend!(executor)
    wait = executor.wait_descriptor || {}
    resume_at = wait['resumeAt']
    @run.update!(status: :waiting, waiting_node_id: executor.waiting_node&.id,
                 wait_reason: wait['reason'], resume_at: resume_at,
                 wait_state: Jabvox::Flows::Engine::WaitState.capture(executor.ctx))
    schedule_wake(resume_at)
    :waiting
  end

  # Despertador puntual. Si falla, el run NO se pierde: queda `waiting` con
  # `resume_at` y el barrido periódico lo recoge.
  def schedule_wake(resume_at)
    return if resume_at.blank?

    Jabvox::Flows::ResumeRunJob.set(wait_until: resume_at).perform_later(@run.id)
  rescue StandardError => e
    Rails.logger.error("No se pudo programar la reanudación del run #{@run.id}: #{e.message}. " \
                       'El barrido periódico lo recogerá.')
  end

  # Toma de posesión ATÓMICA waiting → running: dos despertares simultáneos
  # (job puntual + barrido, o dos respuestas) no ejecutan la continuación dos
  # veces. El segundo ve 0 filas afectadas y sale.
  def claim_for_resume
    claimed = JabvoxFlowRun.where(id: @run.id, status: :waiting)
                           # rubocop:disable Rails/SkipsModelValidations
                           .update_all(status: JabvoxFlowRun.statuses[:running])
    # rubocop:enable Rails/SkipsModelValidations
    @run.reload if claimed.positive?
    claimed.positive?
  end

  def wait_response?
    Jabvox::Flows::Engine::WaitDescriptor.response?(@run.wait_reason)
  end

  def missing_pointer
    @run.update!(status: :failed, finished_at: Time.current,
                 error: 'La ejecución está en espera pero no tiene punto de reanudación.')
    :failed
  end

  # Timeout de espera de RESPUESTA: nadie contestó. NO se continúa por la rama
  # siguiente, porque eso haría indistinguible "me respondieron" de "no".
  def fail_by_timeout(node_id)
    error = 'Se agotó el tiempo de espera de respuesta: nadie respondió antes del timeout configurado.'
    recorder.resolve_waiting_step(node_id, status: :failed, error: error,
                                           output: { 'timedOut' => true, 'resumedAt' => Time.current.iso8601 })
    @run.update!(status: :failed, error: error, finished_at: Time.current, **cleared_pointer)
    :failed
  end

  def continue_from(node_id, payload, timed_out)
    state = Jabvox::Flows::Engine::WaitState.restore(@run.wait_state)
    ctx = build_context(vars: state[:vars], outputs: state[:outputs], trigger: state[:trigger])
    publish_response(ctx, node_id, payload, timed_out)
    # El puntero se limpia ANTES de continuar: si el flujo vuelve a suspenderse
    # más adelante, `suspend!` escribirá el puntero nuevo sin residuos.
    @run.update!(cleared_pointer)

    graph = @run.version.engine_graph
    executor = build_executor(ctx)
    finish(executor.run(trigger_type: 'resume', start_nodes: graph.successors(node_id, 'out')), executor)
  end

  # La respuesta recibida es visible como `{{vars.resume}}` y como salida del
  # nodo de espera: `{{node.<id>.output.response}}`.
  def publish_response(ctx, node_id, payload, timed_out)
    ctx.vars['resume'] = payload
    resolved = { 'response' => payload, 'timedOut' => timed_out == true, 'resumedAt' => Time.current.iso8601 }
    previous = ctx.outputs[node_id]
    ctx.outputs[node_id] = (previous.is_a?(Hash) ? previous : {}).merge(resolved)
    recorder.resolve_waiting_step(node_id, status: :success, output: resolved)
  end

  def cleared_pointer
    { waiting_node_id: nil, wait_reason: nil, resume_at: nil, wait_state: nil }
  end
end
