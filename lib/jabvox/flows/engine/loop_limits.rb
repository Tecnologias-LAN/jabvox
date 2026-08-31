# frozen_string_literal: true

# Límites del bucle (`logic.loop`). Viven aquí para que el catálogo y el motor
# lean el mismo número sin importarse entre sí.
module Jabvox::Flows::Engine::LoopLimits
  # Tope duro de iteraciones: ni configurando más se pasa de aquí.
  HARD_MAX_ITERATIONS = 10_000
  DEFAULT_MAX_ITERATIONS = 1000
  DEFAULT_BATCH_SIZE = 1

  module_function

  # Límite acotado por el tope duro. Inválido → por defecto.
  def max_iterations(raw)
    value = to_int(raw)
    bounded = value&.positive? ? value : DEFAULT_MAX_ITERATIONS
    [bounded, HARD_MAX_ITERATIONS].min
  end

  # Tamaño de lote: entero >= 1. Inválido → 1 (uno a uno).
  def batch_size(raw)
    value = to_int(raw)
    value && value >= 1 ? value : DEFAULT_BATCH_SIZE
  end

  def to_int(raw)
    return nil if raw.nil? || raw == true || raw == false

    Float(raw.to_s).truncate
  rescue ArgumentError, TypeError
    nil
  end

  # Reparte los elementos en lotes del tamaño dado.
  def chunk(items, size)
    return [] if items.empty?

    items.each_slice([1, size.to_i].max).to_a
  end
end
