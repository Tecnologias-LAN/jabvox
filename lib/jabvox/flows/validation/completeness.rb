# frozen_string_literal: true

# Reglas de COMPLETITUD: las que solo se exigen en modo estricto, cuando el
# flujo va a activarse. Viven aparte porque el editor autoguarda a medio
# construir y estas comprobaciones no pueden bloquear ese guardado.
class Jabvox::Flows::Validation::Completeness
  Codes = Jabvox::Flows::Validation::Codes
  Params = Jabvox::Flows::Validation::Params
  References = Jabvox::Flows::Validation::References

  def initialize(validator, graph, by_id, with_incoming)
    @validator = validator
    @graph = graph
    @by_id = by_id
    @with_incoming = with_incoming
  end

  def call
    @by_id.each_value do |node|
      next unless @validator.known_type?(node.type)

      params = effective_params(node)
      validate_required(node, params)
      validate_references(node, params)
      validate_orphan(node)
    end
    validate_loop_back_edges
    validate_cycles
  end

  private

  def registry
    @validator.registry
  end

  def add(...)
    @validator.add(...)
  end

  def label_of(node)
    @validator.label_of(node)
  end

  def spot(node, param: nil)
    Jabvox::Flows::Validation::Issue::Spot.new(
      node_id: node.is_a?(String) ? node : node.id,
      node_label: node.is_a?(String) ? nil : label_of(node), param: param
    )
  end

  def effective_params(node)
    Params.effective(registry ? registry.params_spec(node.type) : [], node.params)
  end

  def validate_required(node, params)
    return if registry.nil?

    registry.params_spec(node.type).each do |spec|
      next unless Params.required?(spec)
      next unless Params.visible?(spec, params)
      next unless Params.empty_value?(params[Params.key_of(spec)])

      add(code: Codes::PARAM_REQUIRED_EMPTY, spot: spot(node, param: Params.key_of(spec)),
          message: "«#{Params.label_of(spec)}» es obligatorio y está vacío.")
    end
  end

  def validate_references(node, params)
    References.in_value(params).each do |ref|
      next if @by_id.key?(ref)

      add(code: Codes::TEMPLATE_UNKNOWN_NODE,
          spot: spot(node, param: References.param_referencing(params, ref)),
          message: "Referencia a un paso inexistente: {{node.#{ref}...}}. Ese paso ya no está en el flujo.")
    end
  end

  # Huérfano: AVISO. Un paso suelto es trabajo en curso normal y bloquear por
  # eso sería hostil.
  def validate_orphan(node)
    return if node.type.to_s.start_with?('trigger.') || @with_incoming.include?(node.id)

    add(code: Codes::NODE_ORPHAN, spot: spot(node), severity: :warning,
        message: 'Este paso no tiene ninguna conexión de entrada: el flujo nunca lo ejecutará.')
  end

  # AVISO, nunca error: hay flujos guardados con esta arista y convertirla en
  # error impediría guardarlos. El bucle ya itera solo; la vuelta es redundante.
  def validate_loop_back_edges
    @by_id.each_value do |node|
      next unless node.loop?

      Jabvox::Flows::Validation::LoopEdges.returning_to(@graph, node.id).each do |from|
        origin = @by_id[from]
        add(code: Codes::LOOP_REDUNDANT_BACK_EDGE, severity: :warning,
            spot: Jabvox::Flows::Validation::Issue::Spot.new(
              node_id: from, node_label: origin ? label_of(origin) : nil
            ),
            message: "Esta conexión vuelve a «#{label_of(node) || node.id}», que ya repite por sí solo una vez " \
                     'por cada elemento. La conexión de vuelta no hace nada y puedes quitarla.')
      end
    end
  end

  # Ciclo que NO es de bucle: el motor no sabe recorrerlo y el run se atascaría.
  def validate_cycles
    Jabvox::Flows::Validation::Cycles.detect(@graph).each do |node_id|
      node = @by_id[node_id]
      next if node.nil?

      add(code: Codes::GRAPH_CYCLE, spot: spot(node),
          message: "«#{label_of(node) || node_id}» forma un ciclo con pasos anteriores. Fuera de un bucle el " \
                   'motor no puede recorrer una conexión que vuelve atrás; usa un paso de bucle.')
    end
  end
end
