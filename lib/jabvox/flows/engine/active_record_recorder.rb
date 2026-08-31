# frozen_string_literal: true

# Persiste la traza del run en `jabvox_flow_run_steps`. Redacta los valores
# secretos y sella a qué iteración del bucle pertenece cada paso, para poder
# inspeccionar cada vuelta después.
class Jabvox::Flows::Engine::ActiveRecordRecorder
  def initialize(run)
    @run = run
  end

  def start_step(node:, ctx:, loop_context: nil)
    @run.steps.create!(
      node_id: node.id, node_type: node.type, status: :running,
      input: Jabvox::Flows::Engine::StepIteration.stamp(
        Jabvox::Flows::Engine::Secrets.redact(node.params || {}, ctx.secret_values), loop_context
      ),
      started_at: Time.current
    )
  end

  def finish_step(step, result:, ctx:)
    step.update!(
      status: step_status(result),
      # Misma redacción en la salida: un handler puede devolver reflejado el
      # secreto que recibió (p. ej. un eco de la petición HTTP).
      output: Jabvox::Flows::Engine::Secrets.redact(result.output, ctx.secret_values),
      error: Jabvox::Flows::Engine::Secrets.redact(result.error, ctx.secret_values),
      finished_at: Time.current
    )
  end

  # El paso saltado queda visible en la traza para que la UI lo explique.
  def skipped_step(node:, ctx:, loop_context: nil)
    @run.steps.create!(
      node_id: node.id, node_type: node.type, status: :skipped,
      input: Jabvox::Flows::Engine::StepIteration.stamp(
        Jabvox::Flows::Engine::Secrets.redact(node.params || {}, ctx.secret_values), loop_context
      ),
      output: { 'skipped' => true }, started_at: Time.current, finished_at: Time.current
    )
  end

  # Cierra el paso que quedó en `waiting` cuando la espera se resuelve (o se
  # rechaza dentro de un bucle), para que la traza no muestre una espera eterna.
  def resolve_waiting_step(node_id, status:, output: {}, error: nil)
    step = @run.steps.where(node_id: node_id, status: :waiting).order(:id).last
    return nil if step.nil?

    previous = step.output.is_a?(Hash) ? step.output : {}
    step.update!(status: status, output: previous.merge(output.stringify_keys),
                 error: error, finished_at: Time.current)
    step
  end

  private

  def step_status(result)
    return :waiting if result.wait?

    result.ok? ? :success : :failed
  end
end
