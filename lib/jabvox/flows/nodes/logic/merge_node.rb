# frozen_string_literal: true

# logic.merge — CONFLUENCIA de ramas. El motor garantiza que se ejecuta cuando
# TODAS sus ramas entrantes se resolvieron; las no tomadas cuentan como vacías.
class Jabvox::Flows::Nodes::Logic::MergeNode < Jabvox::Flows::Nodes::Base
  type 'logic.merge'
  label 'Confluencia'
  items_path 'items'

  def perform
    sources = ctx.incoming_sources_by_node[node.id] || []
    fail_with!('El nodo de confluencia no tiene ramas de entrada conectadas: conéctale al menos una rama.') if
      sources.empty?

    branches = sources.map { |id| { 'id' => id, 'ran' => ctx.outputs.key?(id), 'items' => branch_items(id) } }
    case first_filled(param(:mode), 'append')
    when 'choose' then choose(branches)
    when 'by_key' then by_key(branches)
    else append(branches)
    end
  end

  private

  def with_data(branches)
    branches.select { |b| b['items'].any? }
  end

  def append(branches)
    items = branches.flat_map { |b| b['items'] }
    { 'modo' => 'append', 'ramas' => branches.length, 'ramasConDatos' => with_data(branches).length,
      'count' => items.length, 'items' => items }
  end

  def choose(branches)
    chosen = with_data(branches).first
    { 'modo' => 'choose', 'ramas' => branches.length, 'ramasConDatos' => with_data(branches).length,
      'ramaElegida' => chosen&.fetch('id', nil), 'count' => chosen ? chosen['items'].length : 0,
      'items' => chosen ? chosen['items'] : [] }
  end

  def by_key(branches)
    key = param(:key).to_s.strip
    fail_with!('El modo «unir por clave» necesita la clave común (p.ej. "id").') if key.blank?

    merged = {}
    extras = []
    branches.each { |b| b['items'].each { |item| absorb(item, key, merged, extras) } }
    items = merged.values + extras
    { 'modo' => 'by_key', 'clave' => key, 'ramas' => branches.length,
      'ramasConDatos' => with_data(branches).length, 'count' => items.length,
      'coincidencias' => merged.size, 'sinClave' => extras.length, 'items' => items }
  end

  # Sin la clave no hay con qué casar: se conserva aparte para no perder datos.
  def absorb(item, key, merged, extras)
    value = item.is_a?(Hash) ? item[key] : nil
    return extras << item if value.nil?

    id = value.to_s
    merged[id] = (merged[id] || {}).merge(item)
  end

  # Elementos de una rama con el MISMO contrato de proyección del motor.
  def branch_items(source_id)
    payload = ctx.outputs[source_id]
    return [] if payload.nil?

    path = ctx.items_path_for(source_id)
    at = path ? Jabvox::Flows::Engine::NodeOutput.resolve_path(payload, path) : nil
    return at if at.is_a?(Array)
    return payload if payload.is_a?(Array)
    return payload['items'] if payload.is_a?(Hash) && payload['items'].is_a?(Array)

    [payload]
  end
end
