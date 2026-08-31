/**
 * PORTAPAPELES DEL LIENZO: copiar, cortar y pegar pasos con sus conexiones.
 *
 * Todo lo de aquí son funciones PURAS sobre estructuras planas: no tocan Vue
 * Flow ni el DOM, para poder probarlas en Node.
 */

function numberOr(value, fallback) {
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : fallback;
}

/** Marca del formato propio: distingue el pegado de un JSON cualquiera. */
export const CLIPBOARD_KIND = 'jabvox/flow-clipboard';
export const CLIPBOARD_VERSION = 1;

// ---------------------------------------------------------------------------
// SERIALIZAR
// ---------------------------------------------------------------------------

/**
 * Copia los params descartando lo no serializable: un valor con ciclos no debe
 * tumbar todo el copiado con un TypeError de JSON.stringify.
 */
function safeParams(params) {
  if (!params || typeof params !== 'object') return {};
  return Object.entries(params).reduce((out, [key, value]) => {
    try {
      return { ...out, [key]: JSON.parse(JSON.stringify(value)) };
    } catch {
      return { ...out, [key]: '' };
    }
  }, {});
}

/** Nota adhesiva plana: solo geometría, texto y color. */
function toClipboardNote(note) {
  return {
    id: note.id,
    position: { x: note.position?.x ?? 0, y: note.position?.y ?? 0 },
    width: numberOr(note.width, 260),
    height: numberOr(note.height, 160),
    color: typeof note.color === 'string' ? note.color : 'amber',
    text: typeof note.text === 'string' ? note.text : '',
  };
}

/** Aplana un paso: sin definición del catálogo ni estado de ejecución. */
function toClipboardNode(n) {
  const data = n.data || {};
  return {
    id: n.id,
    position: { x: n.position?.x ?? 0, y: n.position?.y ?? 0 },
    data: {
      nodeType: data.nodeType,
      label: data.label,
      params: safeParams(data.params),
      ...(data.disabled === true ? { disabled: true } : {}),
    },
  };
}

/**
 * Convierte una selección del lienzo en la carga del portapapeles. Solo entran
 * las aristas cuyos DOS extremos están entre los pasos copiados.
 */
export function serializeSelection(nodes, edges, notes = []) {
  const ids = new Set(nodes.map(n => n.id));
  return {
    kind: CLIPBOARD_KIND,
    version: CLIPBOARD_VERSION,
    nodes: nodes.map(toClipboardNode),
    edges: (edges || [])
      .filter(e => ids.has(e.source) && ids.has(e.target))
      .map(e => ({
        id: e.id,
        source: e.source,
        target: e.target,
        ...(e.sourceHandle ? { sourceHandle: e.sourceHandle } : {}),
        ...(e.targetHandle ? { targetHandle: e.targetHandle } : {}),
      })),
    notes: (notes || []).map(toClipboardNote),
  };
}

/** Texto que se pone en el portapapeles del sistema (JSON legible). */
export function serializeToText(nodes, edges, notes) {
  return JSON.stringify(serializeSelection(nodes, edges, notes), null, 2);
}

// ---------------------------------------------------------------------------
// VALIDAR LO PEGADO
// ---------------------------------------------------------------------------

/**
 * Detecta el formato de n8n para poder DECIRLO en vez de fallar con un error
 * genérico: sus nodos traen `typeVersion` y `connections` es un objeto.
 */
function looksLikeN8n(raw) {
  if (Array.isArray(raw.nodes)) {
    const hit = raw.nodes.some(n => {
      if (!n || typeof n !== 'object') return false;
      if (typeof n.typeVersion === 'number') return true;
      return typeof n.type === 'string' && n.type.startsWith('n8n-nodes-base.');
    });
    if (hit) return true;
  }
  const conns = raw.connections;
  return Boolean(conns && typeof conns === 'object' && !Array.isArray(conns));
}

/** Tipo lógico de un paso pegado: 'jabvox' es el componente de render, no el tipo. */
function readNodeType(entry, data) {
  if (typeof data.nodeType === 'string' && data.nodeType) return data.nodeType;
  if (typeof entry.type === 'string' && entry.type !== 'jabvox') {
    return entry.type;
  }
  return '';
}

/** Params de un paso pegado: en `data.params`, o sueltos en la raíz. */
function readParams(entry, data) {
  if (data.params && typeof data.params === 'object') return data.params;
  if (entry.params && typeof entry.params === 'object') return entry.params;
  return {};
}

/**
 * Interpreta un texto pegado y valida ANTES de insertar. Devuelve el motivo
 * exacto del fallo para poder decírselo al usuario.
 *
 * `knownTypes` es el catálogo de esta instalación: los tipos que no estén se
 * devuelven en `unknownTypes`.
 */
export function parseFlowText(text, knownTypes) {
  const trimmed = (text ?? '').trim();
  if (!trimmed) {
    return { ok: false, kind: 'empty' };
  }

  let raw;
  try {
    raw = JSON.parse(trimmed);
  } catch (e) {
    return {
      ok: false,
      kind: 'malformed-json',
      detail: e instanceof Error ? e.message : String(e),
    };
  }

  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return { ok: false, kind: 'not-an-object' };
  }
  if (looksLikeN8n(raw)) return { ok: false, kind: 'n8n-format' };

  // Se acepta la carga del portapapeles y también un `graph` exportado.
  const graph = raw.graph && typeof raw.graph === 'object' ? raw.graph : raw;
  if (!Array.isArray(graph.nodes)) return { ok: false, kind: 'missing-fields' };
  if (graph.edges !== undefined && !Array.isArray(graph.edges)) {
    return { ok: false, kind: 'missing-fields' };
  }

  const nodes = [];
  let badNodes = 0;
  graph.nodes.forEach((entry, i) => {
    if (!entry || typeof entry !== 'object') {
      badNodes += 1;
      return;
    }
    const data = entry.data && typeof entry.data === 'object' ? entry.data : {};
    const nodeType = readNodeType(entry, data);
    if (!nodeType) {
      badNodes += 1;
      return;
    }
    const pos =
      entry.position && typeof entry.position === 'object'
        ? entry.position
        : {};
    nodes.push({
      id: typeof entry.id === 'string' && entry.id ? entry.id : `pegado_${i}`,
      position: { x: numberOr(pos.x, 0), y: numberOr(pos.y, 0) },
      data: {
        nodeType,
        label:
          typeof data.label === 'string' && data.label ? data.label : nodeType,
        params: readParams(entry, data),
        ...(data.disabled === true ? { disabled: true } : {}),
      },
    });
  });

  if (badNodes) return { ok: false, kind: 'missing-fields', badNodes };
  if (!nodes.length && !Array.isArray(graph.notes)) {
    return { ok: false, kind: 'no-nodes' };
  }

  // Aristas colgadas: se descartan (un pegado parcial es normal) pero se
  // RECOGEN en `orphanEdges`: descartar sin decirlo es perder trabajo.
  const nodeIds = new Set(nodes.map(n => n.id));
  const edges = [];
  const orphanEdges = [];
  (Array.isArray(graph.edges) ? graph.edges : []).forEach((entry, i) => {
    if (!entry || typeof entry !== 'object') return;
    const source = typeof entry.source === 'string' ? entry.source : '';
    const target = typeof entry.target === 'string' ? entry.target : '';
    if (!source || !target) {
      orphanEdges.push({
        source: source || '(sin origen)',
        target: target || '(sin destino)',
        missing: [source ? '(sin destino)' : '(sin origen)'],
      });
      return;
    }
    const missing = [];
    if (!nodeIds.has(source)) missing.push(source);
    if (!nodeIds.has(target)) missing.push(target);
    if (missing.length) {
      orphanEdges.push({ source, target, missing });
      return;
    }
    edges.push({
      id: typeof entry.id === 'string' && entry.id ? entry.id : `pegado_e_${i}`,
      source,
      target,
      ...(typeof entry.sourceHandle === 'string'
        ? { sourceHandle: entry.sourceHandle }
        : {}),
      ...(typeof entry.targetHandle === 'string'
        ? { targetHandle: entry.targetHandle }
        : {}),
    });
  });

  const notes = (Array.isArray(graph.notes) ? graph.notes : [])
    .filter(n => n && typeof n === 'object')
    .map(toClipboardNote);

  const unknownTypes = knownTypes
    ? [
        ...new Set(
          nodes.map(n => n.data.nodeType).filter(t => !knownTypes.has(t))
        ),
      ]
    : [];

  return {
    ok: true,
    payload: {
      kind: CLIPBOARD_KIND,
      version: CLIPBOARD_VERSION,
      nodes,
      edges,
      notes,
    },
    unknownTypes,
    orphanEdges,
  };
}

// ---------------------------------------------------------------------------
// REESCRITURA DE REFERENCIAS EN EXPRESIONES
// ---------------------------------------------------------------------------

/**
 * Reescribe las referencias `{{node.<id>…}}` y `{{outputs.<id>…}}` con el mapa
 * de ids viejo→nuevo. Los ids que NO están en el mapa apuntan a pasos que no
 * vinieron en el pegado: se dejan tal cual y se devuelven como ROTOS.
 */
export function rewriteNodeRefs(value, idMap) {
  const broken = [];
  const text = String(value).replace(/\{\{([^}]*)\}\}/g, (match, inner) => {
    const ref = String(inner).trim();
    // `node.<id>.output…` y `outputs.<id>…`: el id es el 2º segmento.
    const m = /^(node|outputs)\.([^.\s]+)(.*)$/.exec(ref);
    if (!m) return match;
    const [, head, oldId, tail] = m;
    const newId = idMap.get(oldId);
    if (newId) return `{{${head}.${newId}${tail}}}`;
    if (!broken.includes(oldId)) broken.push(oldId);
    return match;
  });
  return { text, broken };
}

/**
 * Reescribe las referencias POR NOMBRE. Al renombrar un paso por colisión
 * («Buscar leads» → «Buscar leads 1») los textos que lo nombraban dentro de una
 * expresión tienen que seguirle. Solo dentro de `{{…}}`: fuera es texto libre.
 */
function rewriteNamesIn(text, nameMap) {
  if (!nameMap || nameMap.size === 0 || !text.includes('{{')) return text;
  return text.replace(/\{\{([^}]*)\}\}/g, (_match, inner) =>
    // Solo el nombre ENTRECOMILLADO: `{{node["Buscar leads"].output.x}}`.
    [...nameMap].reduce(
      (ref, [oldName, newName]) =>
        ref
          .split(`"${oldName}"`)
          .join(`"${newName}"`)
          .split(`'${oldName}'`)
          .join(`'${newName}'`),
      `{{${String(inner)}}}`
    )
  );
}

/**
 * Reescribe recursivamente TODAS las cadenas de un param. Los params pueden ser
 * objetos o listas (condiciones, casos de un switch, cabeceras HTTP…).
 */
export function rewriteParamValue(value, idMap, nameMap) {
  const broken = [];

  function walk(v, depth) {
    // Corta a 40: un param más anidado no existe en el catálogo, y así una
    // estructura patológica no desborda la pila.
    if (depth > 40) return v;
    if (typeof v === 'string') {
      const refs = rewriteNodeRefs(v, idMap);
      refs.broken.forEach(id => {
        if (!broken.includes(id)) broken.push(id);
      });
      return rewriteNamesIn(refs.text, nameMap);
    }
    if (Array.isArray(v)) return v.map(item => walk(item, depth + 1));
    if (v && typeof v === 'object') {
      return Object.entries(v).reduce(
        (out, [k, child]) => ({ ...out, [k]: walk(child, depth + 1) }),
        {}
      );
    }
    return v;
  }

  return { value: walk(value, 0), broken };
}

// ---------------------------------------------------------------------------
// PREPARAR EL PEGADO
// ---------------------------------------------------------------------------

/**
 * Primer nombre libre de la serie «X», «X 1», «X 2»… Es lo que espera quien
 * duplica un paso para variarlo un poco.
 */
export function uniqueLabel(base, taken) {
  if (!taken.has(base)) return base;
  // Si ya venía numerado («Buscar leads 2»), se sigue desde ahí.
  const m = /^(.*?)\s+(\d+)$/.exec(base);
  const stem = m ? m[1] : base;
  let i = m ? Number(m[2]) : 0;
  // Cota: con 10 000 nombres iguales algo va muy mal, y es mejor un sufijo con
  // marca de tiempo que colgar el editor en el bucle.
  for (let guard = 0; guard < 10000; guard += 1) {
    i += 1;
    const candidate = `${stem} ${i}`;
    if (!taken.has(candidate)) return candidate;
  }
  return `${stem} ${Date.now().toString(36)}`;
}

/**
 * Prepara una carga para insertarla: ids nuevos, conexiones reapuntadas,
 * referencias reescritas, nombres sin colisión y posiciones desplazadas.
 *
 * Opciones: `existingLabels` (Set), `existingIds` (Set), `offset`, `at`,
 * `makeId(nodeType, taken)`, `makeNoteId(taken)`.
 */
export function preparePaste(payload, opts) {
  const offset = opts.offset ?? { x: 48, y: 48 };

  // 1) Ids nuevos para TODOS los pasos antes de tocar params: una referencia
  //    puede ir hacia adelante, a un paso aún no recorrido.
  const takenIds = new Set(opts.existingIds ?? []);
  const idMap = new Map();
  payload.nodes.forEach(n => {
    const fresh = opts.makeId(n.data.nodeType, takenIds);
    takenIds.add(fresh);
    idMap.set(n.id, fresh);
  });

  // 2) Nombres sin colisión. `taken` crece con cada paso pegado para que dos
  //    pasos del propio pegado tampoco choquen entre sí.
  const taken = new Set(opts.existingLabels ?? []);
  const nameMap = new Map();
  const renamed = new Map();
  const labels = new Map();
  payload.nodes.forEach(n => {
    const original = n.data.label;
    const unique = uniqueLabel(original, taken);
    taken.add(unique);
    labels.set(n.id, unique);
    if (unique === original) return;
    // NO se sobrescribe: con dos pasos del mismo nombre la referencia es
    // ambigua y gana el PRIMERO, igual que hace el motor.
    if (!nameMap.has(original)) nameMap.set(original, unique);
    renamed.set(unique, original);
  });

  // 3) Recolocación: con `at` se traslada el bloque entero conservando las
  //    distancias relativas (su esquina superior izquierda pasa a ser `at`).
  const geometry = [
    ...payload.nodes.map(n => n.position),
    ...(payload.notes ?? []).map(n => n.position),
  ];
  let dx = offset.x;
  let dy = offset.y;
  if (opts.at && geometry.length) {
    dx = opts.at.x - Math.min(...geometry.map(p => p.x));
    dy = opts.at.y - Math.min(...geometry.map(p => p.y));
  }

  // 4) Pasos con ids, nombres, posiciones y params reescritos.
  const brokenRefs = new Map();
  const nodes = payload.nodes.map(n => {
    const newId = idMap.get(n.id);
    const rewritten = rewriteParamValue(n.data.params, idMap, nameMap);
    if (rewritten.broken.length) brokenRefs.set(newId, rewritten.broken);
    return {
      ...n,
      id: newId,
      position: { x: n.position.x + dx, y: n.position.y + dy },
      data: { ...n.data, label: labels.get(n.id), params: rewritten.value },
    };
  });

  // 5) Conexiones reapuntadas. Las que pierden un extremo se RECOGEN para
  //    poder avisar: antes se tiraban en silencio y el usuario perdía trabajo.
  const stamp = Date.now().toString(36);
  const edges = [];
  const droppedEdges = [];
  payload.edges.forEach((e, i) => {
    const missing = [];
    if (!idMap.has(e.source)) missing.push(e.source);
    if (!idMap.has(e.target)) missing.push(e.target);
    if (missing.length) {
      droppedEdges.push({ source: e.source, target: e.target, missing });
      return;
    }
    edges.push({
      ...e,
      id: `e_${idMap.get(e.source)}-${idMap.get(e.target)}-${stamp}_${i}`,
      source: idMap.get(e.source),
      target: idMap.get(e.target),
    });
  });

  // 6) Notas: id nuevo y la misma traslación. No tienen referencias que romper.
  const takenNotes = new Set(opts.existingNoteIds ?? []);
  const notes = (payload.notes ?? []).map(note => {
    const fresh = opts.makeNoteId
      ? opts.makeNoteId(takenNotes)
      : `note_${stamp}_${takenNotes.size}`;
    takenNotes.add(fresh);
    return {
      ...note,
      id: fresh,
      position: { x: note.position.x + dx, y: note.position.y + dy },
    };
  });

  const brokenCount = [...brokenRefs.values()].reduce(
    (total, list) => total + list.length,
    0
  );

  return {
    nodes,
    edges,
    notes,
    brokenRefs,
    renamed,
    brokenCount,
    droppedEdges,
  };
}

// ---------------------------------------------------------------------------
// PORTAPAPELES DEL SISTEMA
// ---------------------------------------------------------------------------

function legacyCopy(text) {
  try {
    const area = document.createElement('textarea');
    area.value = text;
    // Fuera de la vista pero enfocable: `execCommand` no copia de un display:none.
    area.setAttribute('readonly', '');
    area.style.cssText = 'position:fixed;top:-1000px;left:-1000px;opacity:0';
    document.body.appendChild(area);
    area.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(area);
    return ok;
  } catch {
    return false;
  }
}

/**
 * Escribe en el portapapeles. `navigator.clipboard` exige un contexto seguro y
 * permiso, así que hay respaldo con `execCommand` sobre un textarea oculto.
 */
export async function writeClipboardText(text) {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // Permiso denegado o contexto no seguro: se prueba el respaldo.
  }
  return legacyCopy(text);
}

/**
 * Lee el portapapeles. `readText` falla en casi todo navegador sin permiso
 * explícito, por eso el pegado real se sirve del `ClipboardEvent`; esto es solo
 * para el botón «Pegar» de la barra.
 */
export async function readClipboardText() {
  try {
    if (navigator.clipboard?.readText)
      return await navigator.clipboard.readText();
  } catch {
    // Sin permiso: quien llama debe recurrir al evento paste.
  }
  return null;
}
