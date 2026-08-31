# frozen_string_literal: true

# SELLADO DE LA ITERACIÓN en cada paso persistido. Sin esto la traza mostraba N
# filas indistinguibles del mismo nodo y la UI solo podía quedarse con la última.
# Se sella DENTRO del JSON `input` con una clave reservada, así los pasos
# antiguos siguen leyéndose (devuelven nil) y no hace falta migrar columnas.
module Jabvox::Flows::Engine::StepIteration
  STEP_LOOP_KEY = '__bucle'

  module_function

  # Añade el sello a los params ya redactados. Devuelve el mismo valor si no hay
  # bucle en curso: los pasos fuera de un bucle no se tocan.
  def stamp(input, loop_context)
    return input || {} if loop_context.nil?

    base = input.is_a?(Hash) ? input.dup : { 'value' => input }
    base.merge(STEP_LOOP_KEY => loop_context)
  end

  # Lee el contexto sellado. nil en pasos fuera de un bucle y en los anteriores
  # a este sello (compatibilidad).
  def read(input)
    return nil unless input.is_a?(Hash)

    raw = input[STEP_LOOP_KEY]
    return nil unless raw.is_a?(Hash)

    loop_id = raw['loopId'].presence
    return nil if loop_id.nil?

    { 'loopId' => loop_id, 'loopLabel' => raw['loopLabel'].to_s,
      'iteracion' => number_or(raw['iteracion'], 1), 'posicion' => number_or(raw['posicion'], 1),
      'totalElementos' => number_or(raw['totalElementos'], 0),
      'totalIteraciones' => number_or(raw['totalIteraciones'], 0) }
  end

  # `input` sin la clave sellada, tal como el usuario configuró el paso: la UI
  # muestra ESTO como entrada, el sello es metadato del motor.
  def without_loop(input)
    input.is_a?(Hash) ? input.except(STEP_LOOP_KEY) : input
  end

  def number_or(value, fallback)
    value.is_a?(Numeric) ? value : fallback
  end

  # Contexto a sellar a partir del alcance vivo del bucle.
  def context_of(loop_id, loop_label, counters)
    { 'loopId' => loop_id, 'loopLabel' => loop_label.to_s,
      'iteracion' => counters.iteracion, 'posicion' => counters.posicion,
      'totalElementos' => counters.total_elementos, 'totalIteraciones' => counters.total_iteraciones }
  end
end
