# frozen_string_literal: true

# "Ejecutar desde aquí": ejecución normal que arranca en un nodo concreto en vez
# de en el disparador. Aparece en el historial como cualquier otra.
class Jabvox::Flows::RunFromJob < ApplicationJob
  queue_as :jabvox_flows

  def perform(run_id, node_id)
    run = JabvoxFlowRun.find_by(id: run_id)
    return if run.nil? || !run.pending?

    Jabvox::Flows::RunService.new(run).call(trigger_type: 'trigger.__from', start_nodes: [node_id])
  end
end
