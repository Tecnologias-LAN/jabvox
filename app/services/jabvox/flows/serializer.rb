# frozen_string_literal: true

# Serialización al contrato que consume el EDITOR: claves en camelCase e ids
# como TEXTO. El editor trata los ids como opacos, así que enviarlos en texto
# evita que un id grande pierda precisión en JavaScript.
module Jabvox::Flows::Serializer
  module_function

  def flow(flow, with_graph: false)
    payload = {
      'id' => id(flow.id), 'accountId' => flow.account_id, 'name' => flow.name,
      'description' => flow.description, 'status' => flow.status,
      'folderId' => id(flow.folder_id), 'currentVersionId' => id(flow.current_version_id),
      'createdAt' => time(flow.created_at), 'updatedAt' => time(flow.updated_at)
    }
    payload['currentVersion'] = version(flow.current_version) if with_graph && flow.current_version
    payload
  end

  def version(version)
    return nil if version.nil?

    { 'id' => id(version.id), 'flowId' => id(version.flow_id), 'version' => version.version,
      'graph' => graph(version.graph), 'createdBy' => id(version.created_by),
      'createdAt' => time(version.created_at) }
  end

  # Fila del historial: SIN el grafo, con su tamaño y quién la creó.
  def version_summary(version, current_version_id)
    raw = version.graph.is_a?(Hash) ? version.graph : {}
    { 'id' => id(version.id), 'version' => version.version,
      'createdAt' => time(version.created_at), 'createdBy' => version.created_by,
      'createdByName' => version.creator&.name,
      'nodeCount' => Array(raw['nodes']).size, 'edgeCount' => Array(raw['edges']).size,
      'isCurrent' => version.id == current_version_id }
  end

  # El grafo viaja tal cual se guardó: es del editor y solo él lo interpreta.
  # `notes` son notas adhesivas: decoración del lienzo, nunca ejecutables.
  def graph(raw)
    return { 'nodes' => [], 'edges' => [], 'notes' => [] } unless raw.is_a?(Hash)

    { 'nodes' => Array(raw['nodes']), 'edges' => Array(raw['edges']),
      'notes' => Array(raw['notes']) }
  end

  # `flowsCount` permite a la interfaz avisar de cuántos flujos quedarán sueltos
  # antes de borrar la carpeta.
  def folder(folder)
    { 'id' => id(folder.id), 'name' => folder.name, 'accountId' => folder.account_id,
      'flowsCount' => folder.flows.size, 'createdAt' => time(folder.created_at) }
  end

  def run(run)
    { 'id' => id(run.id), 'accountId' => run.account_id, 'flowId' => id(run.flow_id),
      'versionId' => id(run.version_id), 'status' => run.status, 'trigger' => run.trigger,
      'startedAt' => time(run.started_at), 'finishedAt' => time(run.finished_at),
      'error' => run.error, 'createdAt' => time(run.created_at),
      'durationMs' => duration_ms(run.started_at, run.finished_at) }
  end

  # Fila del listado global. `flowName` puede faltar si el flujo se borró.
  def run_list_item(run, flow_name: nil, steps_total: 0, steps_failed: 0)
    run(run).merge(
      'flowName' => flow_name, 'triggerType' => trigger_type(run.trigger),
      'stepsTotal' => steps_total, 'stepsFailed' => steps_failed,
      'isTest' => test?(run.trigger), 'testNodeId' => trigger_meta(run.trigger, 'testNodeId'),
      'runFromNodeId' => trigger_meta(run.trigger, 'fromNodeId')
    )
  end

  # Paso de la traza. `input` va SIN el sello de iteración: se expone aparte en
  # `loop`, que es como la interfaz muestra "iteración K de N".
  def run_step(step, label: nil)
    { 'id' => id(step.id), 'runId' => id(step.flow_run_id), 'nodeId' => step.node_id,
      'nodeType' => step.node_type, 'label' => label, 'status' => step.status,
      'input' => step.configured_input, 'output' => step.output, 'error' => step.error,
      'startedAt' => time(step.started_at), 'finishedAt' => time(step.finished_at),
      'durationMs' => duration_ms(step.started_at, step.finished_at),
      'createdAt' => time(step.created_at), 'loop' => loop_context(step) }
  end

  def loop_context(step)
    raw = step.loop_context
    return nil if raw.blank?

    raw.deep_stringify_keys
  end

  def variable(variable)
    { 'id' => id(variable.id), 'key' => variable.key, 'description' => variable.description,
      'secret' => variable.secret, 'createdAt' => time(variable.created_at),
      'updatedAt' => time(variable.updated_at),
      # El valor de una variable secreta NUNCA sale al navegador.
      'value' => variable.secret ? '••••' : variable.value }
  end

  def validation(result)
    { 'valid' => result.valid?, 'errorCount' => result.error_count,
      'warningCount' => result.warning_count,
      'issues' => result.issues.map { |issue| issue_hash(issue) } }
  end

  # El editor espera `nodeId`/`nodeLabel` siempre presentes, aunque sean nulos.
  def issue_hash(issue)
    { 'nodeId' => issue.node_id, 'nodeLabel' => issue.node_label, 'param' => issue.param,
      'code' => issue.code.to_s, 'severity' => issue.severity.to_s, 'message' => issue.message }
  end

  def trigger_type(trigger)
    return nil unless trigger.is_a?(Hash)

    trigger['type'].presence || trigger['triggerType'].presence
  end

  def trigger_meta(trigger, key)
    trigger.is_a?(Hash) ? trigger[key] : nil
  end

  def test?(trigger)
    trigger.is_a?(Hash) && trigger['isTest'] == true
  end

  def duration_ms(started_at, finished_at)
    return nil if started_at.nil? || finished_at.nil?

    ((finished_at - started_at) * 1000).round
  end

  def id(value)
    value&.to_s
  end

  def time(value)
    value&.iso8601
  end
end
