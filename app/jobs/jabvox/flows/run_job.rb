# frozen_string_literal: true

# Ejecuta un run en segundo plano, en la cola AISLADA de flujos: un bucle largo
# no puede taponar mensajes ni ningún otro servicio (worker sidekiq_flows.yml).
class Jabvox::Flows::RunJob < ApplicationJob
  queue_as :jabvox_flows
  # Techo explícito de reintentos: un fallo de INFRAESTRUCTURA (p. ej. BD caída un
  # instante) reintenta como mucho 3 veces y no 25 (el defecto de Sidekiq), para no
  # retener un slot del worker. Un fallo de NODO no llega aquí: RunService lo captura
  # y deja el run `failed`, así que el job termina OK y no reintenta.
  sidekiq_options retry: 3

  def perform(run_id, trigger_type: 'trigger.manual', trigger_node_id: nil)
    run = JabvoxFlowRun.find_by(id: run_id)
    return if run.nil?
    # Idempotencia: un reintento de Sidekiq no debe repetir un run ya resuelto.
    return unless run.pending? || run.waiting?

    Jabvox::Flows::RunService.new(run).call(trigger_type: trigger_type, trigger_node_id: trigger_node_id)
  end
end
