# frozen_string_literal: true

# logic.loop — resuelve la colección y calcula el PLAN de iteraciones. El
# recorrido de la rama 'loop' lo coordina el motor (LoopRunner).
class Jabvox::Flows::Nodes::Logic::LoopNode < Jabvox::Flows::Nodes::Base
  type 'logic.loop'
  label 'Bucle'
  items_path 'items'
  outputs 'loop', 'done'

  def perform
    items = coerce_items(param(:items))
    fail_with!(not_a_collection_error(param(:items))) if items.nil?

    max = Jabvox::Flows::Engine::LoopLimits.max_iterations(param(:maxIterations))
    batch_size = Jabvox::Flows::Engine::LoopLimits.batch_size(param(:batchSize))
    planned = (items.length.to_f / batch_size).ceil
    fail_with!(over_limit_error(items, batch_size, planned, max)) if planned > max

    { 'items' => items, 'count' => items.length, 'total' => items.length,
      'itemVar' => first_filled(param(:itemVar), 'item'), 'batchSize' => batch_size,
      'plannedIterations' => planned, 'maxIterations' => max, 'truncated' => false,
      'onItemError' => param(:onItemError) == 'continue' ? 'continue' : 'stop' }
  end

  private

  # Array tal cual; nil/'' es colección VACÍA legítima; texto con JSON de array
  # se parsea. Cualquier otra cosa es nil = error de configuración del usuario.
  def coerce_items(raw)
    return raw if raw.is_a?(Array)
    return [] if raw.nil?
    return nil unless raw.is_a?(String)

    coerce_text(raw.strip)
  end

  def coerce_text(trimmed)
    return [] if trimmed.empty?
    return nil unless trimmed.start_with?('[')

    parsed = JSON.parse(trimmed)
    parsed.is_a?(Array) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  # TOPE ALCANZADO: antes se truncaba en silencio y el flujo salía por 'done'
  # como si hubiera terminado. Se detiene diciendo los números.
  def over_limit_error(items, batch_size, planned, max)
    "El bucle necesita #{planned} iteraciones para #{items.length} elemento(s) con lotes de " \
      "#{batch_size}, y el límite está en #{max}. Sube el \"Límite de iteraciones\" (tope duro " \
      "#{Jabvox::Flows::Engine::LoopLimits::HARD_MAX_ITERATIONS}), aumenta el \"Tamaño de lote\" " \
      'o reduce la colección de entrada.'
  end

  # Mira la EXPRESIÓN escrita, no solo el valor: el fallo típico es apuntar a un
  # campo suelto de UN elemento en vez de a la colección.
  def not_a_collection_error(raw)
    expr = (node.params.is_a?(Hash) ? node.params['items'] : nil).to_s.strip
    base = "La \"Colección de elementos\" no es una lista: se recibió #{describe(raw)}. "
    hint_for(expr) || "#{base}#{generic_hint}"
  end

  # `{{node.<id>.output…}}` apunta a UN elemento, nunca a la colección: la
  # colección completa siempre es `{{node.<id>.items}}`.
  def hint_for(expr)
    single = expr.match(/\{\{\s*(?:node|outputs)\.([A-Za-z0-9_-]+)\.output\.[^}]+\}\}/)
    return field_hint(expr, single[1]) if single

    whole = expr.match(/\{\{\s*(?:node|outputs)\.([A-Za-z0-9_-]+)\.output\s*\}\}/)
    whole ? whole_hint(expr, whole[1]) : nil
  end

  def field_hint(expr, node_id)
    "«#{expr}» apunta a un CAMPO de un solo elemento, no a la colección. " \
      "Usa {{node.#{node_id}.items}} para recorrer todos los elementos de ese paso."
  end

  def whole_hint(expr, node_id)
    "«#{expr}» es UN elemento (el primero), no la colección. Usa {{node.#{node_id}.items}}."
  end

  def generic_hint
    'Apunta la "Colección de elementos" a la lista completa de un paso anterior, ' \
      'p.ej. {{node.buscar_leads.items}}.'
  end

  def describe(value)
    case value
    when nil then 'un valor vacío'
    when String then "el texto \"#{value.length > 40 ? "#{value[0, 39]}…" : value}\""
    when Hash then 'un objeto'
    else "#{value.class.name.downcase} (#{value})"
    end
  end
end
