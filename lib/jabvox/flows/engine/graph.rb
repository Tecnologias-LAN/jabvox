# frozen_string_literal: true

# Grafo normalizado de una versión de flujo. El editor persiste cada nodo con
# `type: 'custom'` y el tipo lógico en `data.nodeType`; el motor trabaja SIEMPRE
# sobre esta forma normalizada (type lógico + params).
class Jabvox::Flows::Engine::Graph
  DEFAULT_PORT = 'out'

  Node = Struct.new(:id, :type, :params, :data, keyword_init: true) do
    # El editor marca `data.disabled`; el motor salta el nodo y sigue por 'out'.
    def disabled?
      flag = data.is_a?(Hash) ? (data['disabled'] || data[:disabled]) : nil
      flag = params['__disabled'] if flag.nil? && params.is_a?(Hash)
      flag == true
    end

    def loop?
      type == 'logic.loop'
    end
  end

  Edge = Struct.new(:id, :source, :target, :source_handle, :target_handle, keyword_init: true) do
    def port
      source_handle.presence || DEFAULT_PORT
    end
  end

  attr_reader :nodes, :edges

  def self.normalize(raw)
    raw = {} unless raw.is_a?(Hash)
    raw = raw.deep_stringify_keys
    new(nodes: Array(raw['nodes']).map { |n| build_node(n) },
        edges: Array(raw['edges']).map { |e| build_edge(e) })
  end

  def self.build_node(raw)
    raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    data = raw['data'].is_a?(Hash) ? raw['data'] : {}
    Node.new(id: raw['id'].to_s, type: node_type_of(raw, data),
             params: node_params_of(raw, data), data: data)
  end

  # 'custom' es el componente de render del editor, nunca un tipo lógico: el
  # tipo real vive en `data.nodeType`.
  def self.node_type_of(raw, data)
    declared = data['nodeType'].presence if data['nodeType'].is_a?(String)
    (declared || (raw['type'] == 'custom' ? '' : raw['type'])).to_s
  end

  def self.node_params_of(raw, data)
    return data['params'] if data['params'].is_a?(Hash)

    raw['params'] || {}
  end

  def self.build_edge(raw)
    raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    Edge.new(id: raw['id'].to_s, source: raw['source'].to_s, target: raw['target'].to_s,
             source_handle: raw['sourceHandle'].presence, target_handle: raw['targetHandle'].presence)
  end

  def initialize(nodes:, edges:)
    @nodes = nodes
    @edges = edges
    @by_id = nodes.index_by(&:id)
    @out_by_source = edges.group_by(&:source)
    @in_by_target = edges.group_by(&:target)
  end

  def node(id)
    @by_id[id]
  end

  def node?(id)
    @by_id.key?(id)
  end

  def outgoing(node_id)
    @out_by_source.fetch(node_id, [])
  end

  def incoming(node_id)
    @in_by_target.fetch(node_id, [])
  end

  # Sucesores de un nodo por un puerto de salida concreto.
  def successors(node_id, port)
    outgoing(node_id).select { |e| e.port == port }.map(&:target)
  end
end
