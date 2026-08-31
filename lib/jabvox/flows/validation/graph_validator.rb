# frozen_string_literal: true

# VALIDACIÓN DEL GRAFO — dos modos, un solo motor.
#
# El editor AUTOGUARDA mientras se construye el flujo, así que a media
# construcción siempre habrá params vacíos y pasos sin conectar. Por eso:
#  - :permissive (autoguardado) solo comprueba lo que haría el grafo IMPOSIBLE
#    de cargar: estructura, ids duplicados, tipos desconocidos y aristas colgadas.
#  - :strict (validar y ACTIVAR) añade obligatorios, referencias, puertos,
#    huérfanos, disparadores duplicados y ciclos (ver Completeness).
#
# Se recogen TODOS los problemas y se devuelven juntos. Los avisos no bloquean
# nunca, ni siquiera en estricto.
class Jabvox::Flows::Validation::GraphValidator
  Codes = Jabvox::Flows::Validation::Codes
  Spot = Jabvox::Flows::Validation::Issue::Spot

  MODES = %i[permissive strict].freeze

  attr_reader :registry

  # `raw_graph` es el grafo tal como se guarda (hash). `registry` aporta los
  # tipos conocidos; sin él no se comprueban tipos ni params.
  def self.call(raw_graph, mode: :strict, registry: nil)
    new(raw_graph, mode: mode, registry: registry).call
  end

  def initialize(raw_graph, mode: :strict, registry: nil)
    @raw = raw_graph
    @mode = MODES.include?(mode) ? mode : :strict
    @registry = registry
    @issues = []
  end

  def call
    return result unless well_formed?

    @graph = Jabvox::Flows::Engine::Graph.normalize(@raw)
    validate_nodes
    validate_edges
    validate_triggers
    completeness.call if @mode == :strict
    result
  end

  def add(code:, message:, spot: nil, severity: :error)
    @issues << Jabvox::Flows::Validation::Issue.new(
      code: code, message: message, spot: spot, severity: severity
    )
  end

  # Etiqueta visible: la que puso el usuario, la del catálogo, o el propio tipo.
  def label_of(node)
    custom = node.data.is_a?(Hash) ? node.data['label'] : nil
    return custom.strip if custom.is_a?(String) && custom.strip != ''

    @registry&.label(node.type).presence || node.type.presence
  end

  # Sin registro no se comprueban tipos: la validación estructural sigue valiendo.
  def known_type?(type)
    @registry.nil? || @registry.registered?(type)
  end

  private

  def result
    Jabvox::Flows::Validation::Result.new(@issues, @mode)
  end

  def completeness
    Jabvox::Flows::Validation::Completeness.new(self, @graph, by_id, with_incoming)
  end

  def well_formed?
    return true if @raw.is_a?(Hash) && nodes_raw.is_a?(Array) && edges_raw.is_a?(Array)

    add(code: Codes::GRAPH_MALFORMED,
        message: 'El flujo está mal formado: debe tener una lista de pasos y otra de conexiones.')
    false
  end

  def nodes_raw
    @raw.is_a?(Hash) ? (@raw['nodes'] || @raw[:nodes]) : nil
  end

  def edges_raw
    @raw.is_a?(Hash) ? (@raw['edges'] || @raw[:edges]) : nil
  end

  # Nodos válidos indexados por id. Los inválidos ya quedaron reportados.
  def by_id
    @by_id ||= {}
  end

  def with_incoming
    @with_incoming ||= Set.new
  end

  def spot_of(node, param: nil)
    Spot.new(node_id: node.id, node_label: label_of(node), param: param)
  end

  def validate_nodes
    @graph.nodes.each do |node|
      next missing_id_or_type(node) if node.id.blank? || node.type.blank?
      next duplicate_id(node) if by_id.key?(node.id)

      by_id[node.id] = node
      unknown_type(node) unless known_type?(node.type)
    end
  end

  def missing_id_or_type(node)
    add(code: Codes::NODE_MISSING_ID_OR_TYPE, spot: Spot.new(node_id: node.id.presence),
        message: 'Cada paso necesita un identificador y un tipo.')
  end

  def duplicate_id(node)
    add(code: Codes::NODE_DUPLICATE_ID, spot: spot_of(node), message: "Paso duplicado: #{node.id}.")
  end

  def unknown_type(node)
    add(code: Codes::NODE_UNKNOWN_TYPE, spot: spot_of(node),
        message: "Tipo de paso desconocido: '#{node.type}'.")
  end

  def validate_edges
    @graph.edges.each do |edge|
      source = by_id[edge.source]
      target = by_id[edge.target]
      next dangling_edge(edge, source, target) if source.nil? || target.nil?

      with_incoming << edge.target
      validate_source_handle(edge, source) if @mode == :strict
    end
  end

  def dangling_edge(edge, source, target)
    present = source || target
    add(code: Codes::EDGE_DANGLING,
        spot: present ? spot_of(present) : Spot.new,
        message: "La conexión '#{edge.id}' apunta a un paso que no existe.")
  end

  # Un puerto NO declarado por el tipo se rechaza: es lo que protege los puertos
  # 'loop'/'done' del bucle de una conexión que el motor nunca seguiría.
  def validate_source_handle(edge, source)
    handle = edge.source_handle
    # Un handle ausente significa la salida por defecto: válido siempre.
    return if handle.blank? || @registry.nil? || !@registry.registered?(source.type)

    ports = declared_ports(source)
    return if ports.empty? || ports.include?(handle)

    invalid_handle(source, handle, ports)
  end

  # `logic.switch` deriva sus puertos del param `cases`, no del catálogo.
  def declared_ports(source)
    return Jabvox::Flows::Validation::SwitchPorts.of(source) if source.type == 'logic.switch'

    @registry.outputs(source.type).map(&:to_s)
  end

  def invalid_handle(source, handle, ports)
    add(code: Codes::EDGE_INVALID_SOURCE_HANDLE, spot: spot_of(source),
        message: "La conexión sale por el puerto '#{handle}', que no existe en " \
                 "«#{label_of(source) || source.id}». Salidas válidas: #{ports.join(', ')}.")
  end

  def triggers
    @triggers ||= by_id.values.select { |node| node.type.to_s.start_with?('trigger.') }
  end

  def validate_triggers
    return if by_id.empty?
    return no_trigger if triggers.empty?

    duplicate_triggers if @mode == :strict
  end

  def no_trigger
    add(code: Codes::FLOW_NO_TRIGGER, message: 'El flujo debe tener al menos un disparador.')
  end

  # Dos disparadores del MISMO tipo activos dispararían el flujo dos veces por
  # el mismo suceso.
  def duplicate_triggers
    triggers.group_by(&:type).each do |type, nodes|
      next if nodes.length < 2

      add(code: Codes::FLOW_DUPLICATE_TRIGGER, spot: spot_of(nodes.last),
          message: "Hay #{nodes.length} disparadores del tipo '#{type}'. El flujo arrancaría varias veces " \
                   'por el mismo suceso; deja solo uno.')
    end
  end
end
