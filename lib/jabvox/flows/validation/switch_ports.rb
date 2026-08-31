# frozen_string_literal: true

# Puertos de salida DINÁMICOS de `logic.switch`: el catálogo solo declara
# 'default', pero el motor enruta por el nombre del caso. Se derivan del param
# `cases` para que catálogo, lienzo y motor no puedan desincronizarse.
module Jabvox::Flows::Validation::SwitchPorts
  DEFAULT_PORT = 'default'

  module_function

  # Ids de puerto del nodo switch, con 'default' siempre al final.
  def of(node)
    cases = parse(node.params.is_a?(Hash) ? node.params['cases'] : nil)
    ports = cases.each_with_index.map { |kase, index| port_id(kase, index) }
    (ports.uniq + [DEFAULT_PORT]).uniq
  end

  # Un `output` ausente o vacío se resuelve por POSICIÓN (1-based).
  def port_id(kase, index)
    declared = kase.is_a?(Hash) ? (kase['output'] || kase[:output]) : nil
    declared.is_a?(String) && declared.strip != '' ? declared.strip : "case#{index + 1}"
  end

  # Acepta array, texto JSON del editor y cualquier basura (→ []). Nunca lanza.
  def parse(raw)
    value = raw.is_a?(String) ? parse_json(raw) : raw
    value.is_a?(Array) ? value.select { |c| c.is_a?(Hash) } : []
  end

  def parse_json(text)
    return [] if text.strip == ''

    JSON.parse(text)
  rescue JSON::ParserError
    []
  end
end
