# Soporte de AGRUPACIÓN (paréntesis) para condiciones de filtros/automatizaciones.
# Permite expresar "A AND (B OR C)": un elemento del array de condiciones puede ser
# un GRUPO { type: 'group', query_operator, child_operator, conditions: [ ...planas... ] }.
# El formato plano legacy se conserva intacto (retrocompatibilidad total).
module Filters::ConditionGroupSupport
  extend ActiveSupport::Concern

  # Lee una clave de un hash de condición sin importar símbolo o string (los
  # payloads llegan como ActionController::Parameters o hashes indiferentes).
  def group_attr(hash, key)
    return nil unless hash.respond_to?(:[])

    hash[key.to_sym] || hash[key.to_s]
  end

  # ¿Es un nodo de grupo (paréntesis) y no una condición plana?
  def group?(query_hash)
    group_attr(query_hash, :type).to_s == 'group'
  end

  def group_children(group_hash)
    group_attr(group_hash, :conditions) || []
  end

  def group_child_operator(group_hash)
    normalize_operator(group_attr(group_hash, :child_operator), 'OR')
  end

  # Operador que une el grupo con lo SIGUIENTE. Debe ser AND/OR o vacío (el último
  # elemento no lleva). NUNCA se interpola texto arbitrario en el SQL: cualquier
  # valor que no sea AND/OR se descarta (defensa anti inyección SQL en el filtro de
  # conversaciones, que no tiene un modelo que valide el payload como las reglas).
  def safe_group_operator(group_hash)
    op = group_attr(group_hash, :query_operator).to_s.strip.upcase
    %w[AND OR].include?(op) ? op : ''
  end

  def normalize_operator(value, default)
    op = value.to_s.strip.upcase
    %w[AND OR].include?(op) ? op : default
  end

  # Elimina un AND/OR colgante al final de un fragmento de condición plana.
  def strip_trailing_operator(fragment)
    fragment.sub(/\s+(AND|OR)\s*\z/i, '').strip
  end

  # Aplana las condiciones (expande las hijas de los grupos) para inspección uniforme.
  def flatten_conditions(conditions)
    (conditions || []).flat_map do |obj|
      group?(obj) ? group_children(obj) : [obj]
    end
  end
end
