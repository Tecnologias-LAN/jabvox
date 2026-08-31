# frozen_string_literal: true

# Registrador que NO persiste nada. Permite ejercitar el motor (y sus specs) sin
# tocar la base de datos: el recorrido es lo que se está probando, no la traza.
class Jabvox::Flows::Engine::NullRecorder
  def start_step(node:, ctx:, loop_context: nil)
    { node_id: node.id, loop_context: loop_context, ctx: ctx }
  end

  def finish_step(step, result:, ctx:); end

  def skipped_step(node:, ctx:, loop_context: nil); end

  def resolve_waiting_step(node_id, status:, output: {}, error: nil); end
end
