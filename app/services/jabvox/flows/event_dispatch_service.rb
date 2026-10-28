# frozen_string_literal: true

# Conecta los eventos del sistema (conversación/mensaje/contacto…) con el motor de
# flujos: dado un evento y su payload, encuentra los flujos ACTIVOS de la cuenta
# cuyo trigger `trigger.jabvox_event` coincide (tipo de evento + inbox + filterJson)
# y encola un run por cada uno.
#
# Es el equivalente, para "Automatizaciones avanzadas", del AutomationRuleListener
# del Automations nativo de Chatwoot: misma idea (evento -> reglas que matchean ->
# ejecutar), pero disparando flujos en vez de automation rules.
class Jabvox::Flows::EventDispatchService
  EVENT_TRIGGER_TYPE = 'trigger.jabvox_event'

  def initialize(account:, event_name:, payload:)
    @account = account
    @event_name = event_name.to_s
    # El payload se normaliza a string-keys y se le asegura la clave `event`, que
    # es contra la que matchea JabvoxEventNode.
    @payload = (payload || {}).deep_stringify_keys.merge('event' => @event_name)
  end

  def call
    return unless dispatchable?

    matching_flows.each do |flow, trigger_node|
      enqueue_run(flow, trigger_node)
    end
  end

  private

  def dispatchable?
    return false if @account.blank?
    return false unless @account.feature_enabled?('jabvox_advanced_automations')

    true
  end

  # Flujos activos con un trigger de evento que coincide con este payload.
  # Devuelve pares [flow, trigger_node] porque el run arranca en ese nodo concreto.
  def matching_flows
    JabvoxFlow.where(account_id: @account.id, status: :active)
              .where.not(current_version_id: nil)
              .includes(:current_version)
              .filter_map { |flow| match_for(flow) }
  end

  def match_for(flow)
    version = flow.current_version
    return nil if version.nil?

    node = matching_trigger_node(version)
    node ? [flow, node] : nil
  rescue StandardError => e
    # Un grafo corrupto de un flujo no debe tumbar el despacho de los demás.
    Rails.logger.error("[Flows::EventDispatch] flow=#{flow.id} #{e.class}: #{e.message}")
    nil
  end

  def matching_trigger_node(version)
    version.engine_graph.nodes.find do |node|
      node.type == EVENT_TRIGGER_TYPE &&
        !node.disabled? &&
        Jabvox::Flows::Nodes::Triggers::JabvoxEventNode.matches?(node, @payload)
    end
  end

  def enqueue_run(flow, trigger_node)
    # Guardia anti-bucle: si el flujo se está disparando en bucle (su acción
    # re-genera su propio evento), se auto-pausa y se salta este disparo. Fail-open.
    return if Jabvox::Flows::LoopGuard.tripped?(flow)

    run = JabvoxFlowRun.create!(
      account_id: @account.id, flow: flow, version: flow.current_version,
      status: :pending, trigger: @payload.merge('type' => EVENT_TRIGGER_TYPE),
      triggered_by: nil
    )
    Jabvox::Flows::RunJob.perform_later(run.id, trigger_type: EVENT_TRIGGER_TYPE, trigger_node_id: trigger_node.id)
  rescue StandardError => e
    Rails.logger.error("[Flows::EventDispatch] no se pudo encolar flow=#{flow.id} #{e.class}: #{e.message}")
  end
end
