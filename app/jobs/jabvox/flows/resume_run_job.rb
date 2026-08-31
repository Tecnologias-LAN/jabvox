# frozen_string_literal: true

# Despertador PUNTUAL de un run suspendido. Lo programa el propio motor al
# suspender (`wait_until: resume_at`). El barrido periódico es la red de
# seguridad para cuando este job se pierde.
class Jabvox::Flows::ResumeRunJob < ApplicationJob
  queue_as :jabvox_flows

  def perform(run_id, timed_out: nil)
    run = JabvoxFlowRun.find_by(id: run_id)
    # Idempotencia: si ya lo reanudó el barrido (o una respuesta), no hay nada
    # que hacer. La toma de posesión atómica del servicio lo cubre igualmente.
    return if run.nil? || !run.waiting?

    # El vencimiento solo es un TIMEOUT para la espera de respuesta; para
    # delay/wait_until el plazo cumplido ES el evento esperado.
    fallback = Jabvox::Flows::Engine::WaitDescriptor.response?(run.wait_reason)
    Jabvox::Flows::RunService.new(run).resume(timed_out: timed_out.nil? ? fallback : timed_out)
  end
end
