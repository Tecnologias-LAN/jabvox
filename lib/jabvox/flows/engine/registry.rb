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
  Definition = Struct.new(:type, :handler, :items_path, :outputs, :label, :params, :alias_of, keyword_init: true) do
    # Un tipo es disparador por su prefijo: el catálogo no necesita declararlo.
    def trigger?
      type.to_s.start_with?('trigger.')
    end

    # Un alias es un nombre VIEJO que resuelve al mismo handler que un tipo
    # canónico (compatibilidad con flujos ya guardados). No es un tipo de catálogo.
    def alias?
      alias_of.present?
    end
  end

  def initialize
    @definitions = {}
  end

  # `meta` agrupa los metadatos del catálogo: items_path, outputs, label y params.
  # `alias_of:` marca este tipo como alias de compatibilidad de un canónico: sigue
  # siendo ejecutable (handler resoluble) pero no cuenta como tipo de catálogo.
  def register(type, handler: nil, alias_of: nil, **meta, &block)
    @definitions[type] = Definition.new(
      type: type, handler: handler || block, items_path: meta[:items_path],
      outputs: meta[:outputs] || [], label: meta[:label], params: meta[:params] || [],
      alias_of: alias_of
    )
    self
  end

  # Tipos CANÓNICOS registrados (sin los alias de compatibilidad): es lo que el
  # catálogo lista y contra lo que se valida la paridad catálogo<->motor. La
  # validación de tipos desconocidos usa `registered?`, que SÍ acepta alias.
  def types
    @definitions.reject { |_type, definition| definition.alias? }.keys
  end

  # Todos los tipos incluyendo alias (para diagnósticos / validación permisiva).
  def all_types
    @definitions.keys
  end

  # Alias -> canónico, para resolver un nombre viejo guardado en un flujo.
  def canonical(type)
    @definitions[type]&.alias_of || type
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
