# frozen_string_literal: true

# Ejecuta un run en segundo plano, en la cola AISLADA de flujos: un bucle largo
# no puede taponar mensajes ni ningún otro servicio (worker sidekiq_flows.yml).
class Jabvox::Flows::RunJob < ApplicationJob
  queue_as :jabvox_flows

  def perform(run_id, trigger_type: 'trigger.manual')
    run = JabvoxFlowRun.find_by(id: run_id)
    return if run.nil?
    # Idempotencia: un reintento de Sidekiq no debe repetir un run ya resuelto.
    return unless run.pending? || run.waiting?

    Jabvox::Flows::RunService.new(run).call(trigger_type: trigger_type)
  end
end
