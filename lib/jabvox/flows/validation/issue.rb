# frozen_string_literal: true

# Un problema concreto localizado en el grafo. El `code` es ESTABLE: la interfaz
# lo usa para agrupar e iconizar, y viaja en la respuesta de la API.
class Jabvox::Flows::Validation::Issue
  SEVERITIES = %i[error warning].freeze

  # Dónde está el problema. `node_id` nil = el problema es del grafo entero.
  Spot = Struct.new(:node_id, :node_label, :param, keyword_init: true)

  attr_reader :code, :severity, :message, :spot

  def initialize(code:, message:, spot: nil, severity: :error)
    @code = code
    @message = message
    @spot = spot || Spot.new
    @severity = severity
  end

  def node_id
    @spot.node_id
  end

  def node_label
    @spot.node_label
  end

  def param
    @spot.param
  end

  def error?
    @severity == :error
  end

  def warning?
    @severity == :warning
  end

  def to_h
    { 'nodeId' => node_id, 'nodeLabel' => node_label, 'param' => param,
      'code' => code.to_s, 'severity' => severity.to_s, 'message' => message }.compact
  end
end
