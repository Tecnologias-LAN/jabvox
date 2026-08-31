# frozen_string_literal: true

# Presentación del historial de ejecuciones: resumen para las tarjetas y el
# detalle con la traza que el editor pinta sobre el lienzo.
module Jabvox::Flows::RunPresenter
  Serializer = Jabvox::Flows::Serializer

  module_function

  # Las PRUEBAS de un paso quedan fuera de todas las métricas y se cuentan aparte.
  def stats(days, production, window)
    by_status = production.group_by(&:status).transform_values(&:size)
    finished = by_status.values_at('success', 'failed').compact.sum
    { 'days' => days, 'total' => production.size, 'success' => by_status['success'].to_i,
      'failed' => by_status['failed'].to_i, 'running' => by_status['running'].to_i,
      'waiting' => by_status['waiting'].to_i, 'pending' => by_status['pending'].to_i,
      'successRate' => success_rate(by_status['success'].to_i, finished),
      'last24h' => last24h(production), 'tests' => window.size - production.size }
  end

  def success_rate(success, finished)
    return nil if finished.zero?

    ((success * 100.0) / finished).round(1)
  end

  def last24h(production)
    recent = production.select { |run| run.created_at >= 24.hours.ago }
    { 'total' => recent.size, 'success' => recent.count { |r| r.status == 'success' },
      'failed' => recent.count { |r| r.status == 'failed' } }
  end

  # Lleva el grafo EXACTO que se ejecutó, no el actual del flujo: es lo que
  # permite pintar la ejecución tal como ocurrió aunque el flujo cambiara después.
  def detail(run)
    labels = labels_by_node(run.version)
    steps = run.steps.order(:id).map { |s| Serializer.run_step(s, label: labels[s.node_id]) }

    Serializer.run(run)
              .merge(origin(run))
              .merge('steps' => steps, 'nodes' => group_by_node(steps, labels))
  end

  # De dónde vino la ejecución y contra qué versión corrió.
  def origin(run)
    { 'flowName' => run.flow&.name, 'triggerType' => Serializer.trigger_type(run.trigger),
      'triggeredByUser' => user_ref(run.triggerer),
      'graph' => run.version ? Serializer.graph(run.version.graph) : nil,
      'flowVersion' => run.version&.version,
      'flowCurrentVersion' => run.flow&.current_version&.version,
      'isTest' => Serializer.test?(run.trigger),
      'testNodeId' => Serializer.trigger_meta(run.trigger, 'testNodeId'),
      'runFromNodeId' => Serializer.trigger_meta(run.trigger, 'fromNodeId') }
  end

  # Traza agrupada por paso con TODAS sus vueltas: deja recorrer "iteración K de
  # N" en vez de ver solo la última. Se abre por defecto la primera fallida.
  def group_by_node(steps, labels)
    steps.group_by { |s| s['nodeId'] }.map do |node_id, group|
      failed = group.index { |s| s['status'] == 'failed' }
      { 'nodeId' => node_id, 'nodeType' => group.first['nodeType'], 'label' => labels[node_id],
        'total' => group.size, 'defaultIndex' => failed || (group.size - 1),
        'loopId' => group.first.dig('loop', 'loopId'),
        'steps' => group.each_with_index.map { |s, i| s.merge('attempt' => i + 1) } }
    end
  end

  def labels_by_node(version)
    return {} if version.nil?

    Array(version.graph['nodes']).each_with_object({}) do |node, acc|
      acc[node['id']] = node.dig('data', 'label').presence
    end
  end

  def user_ref(user)
    return nil if user.nil?

    { 'id' => user.id, 'email' => user.email, 'name' => user.name }
  end
end
