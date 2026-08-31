# frozen_string_literal: true

# Registro de handlers por tipo de nodo. En esta etapa el motor no trae ningún
# nodo Jabvox: los tipos se registran desde fuera (y los specs registran los
# suyos), de modo que el núcleo del recorrido no depende del catálogo.
class Jabvox::Flows::Engine::Registry
  # Metadatos por tipo que el motor SÍ necesita conocer del catálogo:
  #  - items_path: dirige la proyección única de `{{node.<id>.output}}`.
  #  - outputs: puertos declarados; el primero es el puerto por defecto.
  #  - params: especificación declarativa que usa la VALIDACIÓN del grafo
  #    (obligatorios, defaults y visibilidad condicional). Vacía = sin exigencias.
  Definition = Struct.new(:type, :handler, :items_path, :outputs, :label, :params, keyword_init: true) do
    # Un tipo es disparador por su prefijo: el catálogo no necesita declararlo.
    def trigger?
      type.to_s.start_with?('trigger.')
    end
  end

  def initialize
    @definitions = {}
  end

  # `meta` agrupa los metadatos del catálogo: items_path, outputs, label y params.
  def register(type, handler: nil, **meta, &block)
    @definitions[type] = Definition.new(
      type: type, handler: handler || block, items_path: meta[:items_path],
      outputs: meta[:outputs] || [], label: meta[:label], params: meta[:params] || []
    )
    self
  end

  # Tipos registrados: la validación los usa para detectar tipos desconocidos.
  def types
    @definitions.keys
  end

  # Puertos de salida declarados por el tipo.
  def outputs(type)
    Array(@definitions[type]&.outputs)
  end

  # Especificación de params del tipo (para la validación de obligatorios).
  def params_spec(type)
    Array(@definitions[type]&.params)
  end

  def definition(type)
    @definitions[type]
  end

  def handler(type)
    @definitions[type]&.handler
  end

  def registered?(type)
    @definitions.key?(type)
  end

  def items_path(type)
    @definitions[type]&.items_path
  end

  def label(type)
    @definitions[type]&.label
  end

  # Puerto por defecto del tipo (primer output declarado), o 'out'.
  def default_port(type)
    @definitions[type]&.outputs&.first || Jabvox::Flows::Engine::Graph::DEFAULT_PORT
  end
end
