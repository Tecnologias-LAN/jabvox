# frozen_string_literal: true

# Referencias `{{node.<id>...}}` dentro de los params. La validación las extrae
# para comprobar que apuntan a nodos que EXISTEN en el grafo.
module Jabvox::Flows::Validation::References
  # Se acepta también `outputs.<id>` por los flujos guardados con la grafía antigua.
  NODE_REF = /\{\{\s*(?:node|outputs)\.([A-Za-z0-9_\-:.]+?)(?:\.|\s*\}\})/

  module_function

  # Ids de nodo referenciados dentro de un valor cualquiera (recursivo).
  def in_value(value, found = Set.new)
    case value
    when String then value.scan(NODE_REF) { |(id)| found << id }
    when Array then value.each { |v| in_value(v, found) }
    when Hash then value.each_value { |v| in_value(v, found) }
    end
    found
  end

  # Primer param del nodo cuyo valor contiene la referencia, para que el aviso
  # apunte al campo concreto y no solo al nodo.
  def param_referencing(params, ref)
    params.find { |_key, value| in_value(value).include?(ref) }&.first
  end
end
