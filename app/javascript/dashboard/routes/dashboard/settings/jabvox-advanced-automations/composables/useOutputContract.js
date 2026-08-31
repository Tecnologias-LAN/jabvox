// CONTRATO DE REFERENCIAS de la salida de un paso. Es la ÚNICA autoridad del
// editor sobre qué significa `output`: con `itemsPath` declarado y resuelto,
// `{{node.<id>.output}}` es UN ELEMENTO y los metadatos van a `.meta.*`.

export const REFERENCE_KEYS = Object.freeze({
  output: 'output',
  meta: 'meta',
  items: 'items',
  raw: 'raw',
});

export const MAX_FIELD_DEPTH = 4;
export const MAX_FIELDS = 400;
const SAMPLE_MAX_LEN = 120;

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function fieldTypeOf(value) {
  if (value === null || value === undefined) return 'null';
  if (Array.isArray(value)) return 'array';
  if (typeof value === 'number') return 'number';
  if (typeof value === 'boolean') return 'boolean';
  if (typeof value === 'object') return 'object';
  return 'string';
}

function sampleOf(value) {
  if (typeof value === 'string' && value.length > SAMPLE_MAX_LEN) {
    return `${value.slice(0, SAMPLE_MAX_LEN)}…`;
  }
  if (Array.isArray(value)) return `[${value.length}]`;
  if (isPlainObject(value)) return `{${Object.keys(value).length}}`;
  return value ?? null;
}

// Una clave con puntos o espacios no se puede unir con un punto: `contact.name`
// sería indistinguible de la clave literal "contact.name". Se escapa siempre.
export function isSafeKey(key) {
  return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key);
}

export function joinPath(prefix, key) {
  if (isSafeKey(key)) return prefix === '' ? key : `${prefix}.${key}`;
  const quoted = `["${key.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"]`;
  return `${prefix}${quoted}`;
}

// Única lectura de rutas del editor: deshace el escapado de `joinPath` y los
// índices de array. Si dos sitios partieran las rutas distinto volvería el bug.
export function splitPath(path) {
  const out = [];
  let current = '';
  let i = 0;

  while (i < path.length) {
    const ch = path[i];

    if (ch === '.') {
      if (current !== '') out.push(current);
      current = '';
      i += 1;
    } else if (ch === '[') {
      if (current !== '') out.push(current);
      current = '';
      i += 1;
      const quote = path[i] === '"' || path[i] === "'" ? path[i] : null;
      if (quote) {
        i += 1;
        let key = '';
        while (i < path.length && path[i] !== quote) {
          if (path[i] === '\\' && i + 1 < path.length) {
            key += path[i + 1];
            i += 2;
          } else {
            key += path[i];
            i += 1;
          }
        }
        i += 1;
        out.push(key);
      } else {
        let key = '';
        while (i < path.length && path[i] !== ']') {
          key += path[i];
          i += 1;
        }
        out.push(key.trim());
      }
      if (path[i] === ']') i += 1;
    } else {
      current += ch;
      i += 1;
    }
  }

  if (current !== '') out.push(current);
  return out;
}

// Atraviesa arrays además de objetos: `items[0].id` debe poder resolver.
export function resolvePath(source, path) {
  return splitPath(path).reduce((current, segment) => {
    if (current === null || current === undefined) return undefined;
    if (typeof current !== 'object') return undefined;
    return current[segment];
  }, source);
}

function collectFields(value, prefix, depth, out) {
  if (out.length >= MAX_FIELDS) return;
  if (!isPlainObject(value)) return;

  Object.entries(value).forEach(([key, child]) => {
    if (out.length >= MAX_FIELDS) return;
    const path = joinPath(prefix, key);
    const expandable =
      depth + 1 < MAX_FIELD_DEPTH &&
      isPlainObject(child) &&
      Object.keys(child).length > 0;

    out.push({
      path,
      label: key,
      type: fieldTypeOf(child),
      sample: sampleOf(child),
      leaf: !expandable,
      depth,
    });

    if (expandable) collectFields(child, path, depth + 1, out);
  });
}

// Reproduce `Jabvox::Flows::Engine::NodeOutput.describe`. Se usa como RESERVA
// cuando el payload llega sin contrato servido (historial de ejecuciones).
export function describeNodeOutput(payload, itemsPath) {
  const declared =
    typeof itemsPath === 'string' && itemsPath.trim() !== ''
      ? itemsPath.trim()
      : null;

  let items;
  let metadata = {};
  let resolved = false;

  if (declared !== null) {
    const candidate = resolvePath(payload, declared);
    if (Array.isArray(candidate)) {
      items = candidate;
      resolved = true;
      const rootKey = splitPath(declared)[0];
      if (isPlainObject(payload)) {
        Object.entries(payload).forEach(([key, value]) => {
          if (key !== rootKey) metadata[key] = value;
        });
      }
    } else {
      items = payload === undefined ? [] : [payload];
    }
  } else {
    items = payload === undefined ? [] : [payload];
  }

  const fieldsOfItem = [];
  collectFields(items.length > 0 ? items[0] : undefined, '', 0, fieldsOfItem);

  if (!isPlainObject(payload)) metadata = {};

  return {
    items,
    itemCount: items.length,
    metadata,
    fieldsOfItem,
    fieldCount: fieldsOfItem.filter(f => f.depth === 0).length,
    itemsPath: declared,
    itemsPathResolved: resolved,
  };
}

// El backend serializa el contrato en snake_case; se normaliza aquí para que el
// resto del editor lea siempre las mismas claves.
function normalizeServed(served) {
  if (!served) return null;
  const items = Array.isArray(served.items) ? served.items : [];
  const fields = served.fieldsOfItem ?? served.fields_of_item ?? [];
  return {
    items,
    itemCount: served.itemCount ?? served.item_count ?? items.length,
    metadata: served.metadata ?? {},
    fieldsOfItem: Array.isArray(fields) ? fields : [],
    fieldCount:
      served.fieldCount ??
      served.field_count ??
      (Array.isArray(fields) ? fields.filter(f => f.depth === 0).length : 0),
    itemsPath: served.itemsPath ?? served.items_path ?? null,
    itemsPathResolved:
      served.itemsPathResolved ?? served.items_path_resolved ?? false,
  };
}

// Contrato EFECTIVO: el servido por el motor si lo hay, y si no la proyección
// de reserva. Único punto donde se decide, para que todas las vistas coincidan.
export function effectiveContract(served, payload, itemsPath) {
  return normalizeServed(served) ?? describeNodeOutput(payload, itemsPath);
}

// Campos del elemento en el índice dado: el panel muestra el SELECCIONADO.
export function fieldsOfItemAt(shape, index) {
  if (index <= 0) return shape.fieldsOfItem;
  const item = shape.items[index];
  if (item === undefined) return shape.fieldsOfItem;
  const out = [];
  collectFields(item, '', 0, out);
  return out;
}

// Texto corto de un valor, en una sola línea.
export function shortValue(value, max = 60) {
  if (value === undefined) return '';
  if (value === null) return 'null';
  if (typeof value === 'string') {
    const text = value.replace(/\s+/g, ' ');
    return text.length > max ? `${text.slice(0, max)}…` : text;
  }
  if (typeof value === 'number' || typeof value === 'boolean')
    return String(value);
  if (Array.isArray(value)) return `[${value.length}]`;
  if (isPlainObject(value)) return `{${Object.keys(value).length}}`;
  return String(value);
}
