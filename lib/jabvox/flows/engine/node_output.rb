# frozen_string_literal: true

# PROYECCIÓN ÚNICA de la salida de un nodo. Única autoridad de qué significa
# `output`: con `items_path` declarado y resuelto es EL ELEMENTO, los metadatos
# van a `meta` y la colección a `items`. Equivocarse aquí genera referencias que
# no resuelven, que es el bug que ya se sufrió en la versión TypeScript.
module Jabvox::Flows::Engine::NodeOutput
  MAX_FIELD_DEPTH = 4
  MAX_FIELDS = 400
  SAMPLE_MAX_LEN = 120

  # Claves del contrato de referencias: output / meta / items / raw.
  REFERENCE_KEYS = { output: 'output', meta: 'meta', items: 'items', raw: 'raw' }.freeze

  module_function

  # Describe la salida separando ELEMENTOS de METADATOS. Sin `items_path` (o si
  # no resuelve a un array), el payload entero es UN elemento: es lo correcto
  # para los nodos de acción simple, que devuelven un objeto y no una lista.
  def describe(payload, items_path = nil)
    declared = items_path.is_a?(String) && items_path.strip != '' ? items_path.strip : nil
    items, metadata, resolved = split_items(payload, declared)
    fields = []
    collect_fields(items.first, '', 0, fields)

    { items: items, item_count: items.length, metadata: metadata, fields_of_item: fields,
      # El conteo que la UI muestra es el de campos de PRIMER NIVEL del elemento.
      field_count: fields.count { |f| f[:depth].zero? },
      items_path: declared, items_path_resolved: resolved }
  end

  def split_items(payload, declared)
    return [payload.nil? ? [] : [payload], {}, false] if declared.nil?

    candidate = resolve_path(payload, declared)
    return [payload.nil? ? [] : [payload], metadata_of(payload, nil), false] unless candidate.is_a?(Array)

    [candidate, metadata_of(payload, declared), true]
  end

  # Metadatos: claves de primer nivel que NO son la colección. Con una ruta
  # anidada se excluye la raíz completa de esa ruta.
  def metadata_of(payload, declared)
    return {} unless payload.is_a?(Hash)
    return {} if declared.nil?

    root_key = declared.split('.').first
    payload.except(root_key)
  end

  # Resuelve una ruta con puntos. `nil` si algún tramo no existe: un payload
  # raro debe poder pintarse, nunca lanzar.
  def resolve_path(source, path)
    path.to_s.split('.').reject(&:empty?).reduce(source) do |current, part|
      return nil unless current.is_a?(Hash)

      current[part]
    end
  end

  def field_type_of(value)
    case value
    when nil then 'null'
    when Array then 'array'
    when Numeric then 'number'
    when true, false then 'boolean'
    when Hash then 'object'
    else 'string'
    end
  end

  def sample_of(value)
    case value
    when String then value.length > SAMPLE_MAX_LEN ? "#{value[0, SAMPLE_MAX_LEN]}…" : value
    when Array then "[#{value.length}]"
    when Hash then "{#{value.keys.length}}"
    else value
    end
  end

  # Recorre el elemento acumulando campos. Los objetos anidados aparecen como
  # campo propio (no hoja) Y se expanden: el árbol muestra `contact` y `contact.name`.
  def collect_fields(value, prefix, depth, out)
    return if out.length >= MAX_FIELDS
    return unless value.is_a?(Hash)

    value.each do |key, child|
      break if out.length >= MAX_FIELDS

      path = prefix == '' ? key.to_s : "#{prefix}.#{key}"
      expandable = expandable?(child, depth)
      out << field_entry(path, key, child, depth, expandable)
      collect_fields(child, path, depth + 1, out) if expandable
    end
  end

  # ¿El hijo se expande como subárbol propio? Solo objetos con contenido y
  # dentro del tope de profundidad.
  def expandable?(child, depth)
    depth + 1 < MAX_FIELD_DEPTH && child.is_a?(Hash) && child.any?
  end

  def field_entry(path, key, child, depth, expandable)
    { path: path, label: key.to_s, type: field_type_of(child),
      sample: sample_of(child), leaf: !expandable, depth: depth }
  end

  # Vista de UNA salida de nodo para las referencias. La consumen el resolvedor
  # de plantillas y el evaluador de expresiones.
  def project_reference(payload, items_path = nil, item_index = 0)
    shape = describe(payload, items_path)
    element = shape[:items_path_resolved] ? shape[:items][item_index] : (shape[:items].first || payload)

    view = {}
    # Compatibilidad: los campos directos del payload crudo siguen accesibles
    # como `{{node.<id>.<campo>}}`; los flujos guardados no se rompen.
    view.merge!(payload.transform_keys(&:to_s)) if payload.is_a?(Hash)
    view[REFERENCE_KEYS[:output]] = element
    view[REFERENCE_KEYS[:meta]] = shape[:metadata]
    view[REFERENCE_KEYS[:items]] = shape[:items]
    view[REFERENCE_KEYS[:raw]] = payload
    view
  end

  # Describe la salida Y el contrato de referencias en una sola llamada, para que
  # la UI y el resolvedor no mantengan dos copias sincronizadas «por disciplina».
  def reference_contract(payload, items_path = nil)
    describe(payload, items_path).merge(reference_root: 'output', reference_keys: REFERENCE_KEYS)
  end
end
