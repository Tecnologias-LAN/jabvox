# frozen_string_literal: true

# Barrido por minuto de los disparadores programados. Recorre los flujos ACTIVOS
# con un `trigger.schedule` y encola un run por cada nodo al que le toca ahora,
# evaluando la hora en la ZONA de cada nodo.
class Jabvox::Flows::TriggerScheduledFlowsJob < ApplicationJob
  queue_as :jabvox_flows_scheduled

  def perform
    now = Time.current.change(sec: 0)
    JabvoxFlow.where(status: :active).where.not(current_version_id: nil)
              .includes(:current_version).find_each { |flow| fire_due_nodes(flow, now) }
  end

  private

  def fire_due_nodes(flow, now)
    scheduled_nodes(flow).each do |node|
      next unless due?(node, now)

      enqueue_run(flow, node, now)
    end
  rescue StandardError => e
    # Un flujo con el grafo corrupto no puede detener el barrido de los demás.
    Rails.logger.error("Barrido programado: fallo en el flujo #{flow.id}: #{e.message}")
  end

  def scheduled_nodes(flow)
    flow.current_version.engine_graph.nodes.select do |node|
      node.type == 'trigger.schedule' && !node.disabled?
    end
  end

  def due?(node, now)
    Jabvox::Flows::Schedule::Matcher.fire?(
      Jabvox::Flows::Schedule::Config.from_params(node.params), now
    )
  end

  # Idempotencia: la unicidad por (flujo, nodo, minuto) evita que dos barridos
  # solapados disparen el mismo instante dos veces.
  def enqueue_run(flow, node, now)
    return unless claim(flow, node, now)

    run = JabvoxFlowRun.create!(
      account_id: flow.account_id, flow: flow, version: flow.current_version,
      trigger: { 'tipo' => 'trigger.schedule', 'nodeId' => node.id, 'instante' => now.iso8601 }
    )
    Jabvox::Flows::RunJob.perform_later(run.id, trigger_type: 'trigger.schedule')
  end

  def claim(flow, node, now)
    key = "jabvox:flows:schedule:#{flow.id}:#{node.id}:#{now.utc.strftime('%Y%m%d%H%M')}"
    Redis::Alfred.set(key, 1, nx: true, ex: 120)
  rescue StandardError
    # Sin Redis el barrido sigue funcionando; el riesgo es un disparo repetido.
    true
  end
end
