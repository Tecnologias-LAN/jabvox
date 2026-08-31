<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { VueFlow, useVueFlow, MarkerType } from '@vue-flow/core';
import { Background } from '@vue-flow/background';
import { Controls } from '@vue-flow/controls';
// El CSS de la librería es MECÁNICA, no estética: sin él el pane no lleva
// `transform-origin: 0 0` (el zoom desplaza los pasos) ni los paneles son
// absolutos (los controles caían en mitad del lienzo). Solo toca `.vue-flow*`.
import '@vue-flow/core/dist/style.css';
import '@vue-flow/controls/dist/style.css';
import { useAlert } from 'dashboard/composables';
import { useFlowsStore, graphIssues } from 'dashboard/store/jabvox/flows/flows';
import { flowsAPI } from 'dashboard/api/jabvox/flows';
import { useNodesStore } from 'dashboard/store/jabvox/flows/nodes';
import FlowNode from './components/FlowNode.vue';
import NodePalette from './components/NodePalette.vue';
import NodeDetailView from './components/NodeDetailView.vue';
import RunHistory from './components/RunHistory.vue';
import StickyNote from './components/StickyNote.vue';
import VersionHistory from './components/VersionHistory.vue';
import { flowStatusStyle, formatDateTime } from './composables/useFlowDesign';
import {
  createAutosaveScheduler,
  graphFingerprint,
} from './composables/useFlowAutosave';
import {
  NOTE_DEFAULTS,
  freeNotePosition,
  nextNoteId,
  normalizeNote,
  serializeNote,
} from './composables/useFlowNotes';
import {
  parseFlowText,
  preparePaste,
  readClipboardText,
  serializeToText,
  writeClipboardText,
} from './composables/useFlowClipboard';

// Editor de flujos: lienzo Vue Flow + paleta + panel de configuración. El grafo
// se guarda como una versión nueva; validar y activar los resuelve el backend.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const flowsStore = useFlowsStore();
const nodesStore = useNodesStore();

// El id ES OBLIGATORIO: `useVueFlow()` aquí se ejecuta ANTES de que <VueFlow>
// haga su `provide`, así que sin id crearía un store aparte y el viewport que
// leemos (notas, <Background>) no sería el del lienzo.
const CANVAS_ID = 'jabvox-flow-canvas';

const {
  onConnect,
  addEdges,
  project,
  vueFlowRef,
  viewport,
  getSelectedNodes,
  removeSelectedElements,
  addSelectedNodes,
  findNode,
} = useVueFlow(CANVAS_ID);

const flowId = computed(() => route.params.flowId);
const nodes = ref([]);
const edges = ref([]);
const selectedId = ref(null);
const issues = ref([]);
const testResult = ref(null);
const loading = ref(true);
const testing = ref(false);
const running = ref(false);
const validating = ref(false);
const showIssues = ref(true);
const menuOpen = ref(false);
const historyRef = ref(null);
const versionsRef = ref(null);
const versionsOpen = ref(false);
const flow = computed(() => flowsStore.current);

const selectedNode = computed(
  () => nodes.value.find(n => n.id === selectedId.value) || null
);

// ---- Vista de detalle en tres columnas (doble clic sobre un paso) ----

// Paso cuyo detalle está abierto; null = la vista está cerrada.
const detailId = ref(null);
const detailNode = computed(
  () => nodes.value.find(n => n.id === detailId.value) || null
);

// Salidas conocidas por paso: se guardan las pruebas para que el panel de
// entrada del paso SIGUIENTE tenga con qué trabajar.
const outputs = ref({});

function nodeById(id) {
  return nodes.value.find(n => n.id === id) || null;
}

// Salida conocida de un paso: la prueba si la hay, y si no el EJEMPLO del
// catálogo. El ejemplo sirve para mapear porque la referencia es idéntica.
function outputFor(nodeId) {
  if (!nodeId) return null;
  const known = outputs.value[nodeId];
  if (known) return known;
  const node = nodeById(nodeId);
  const sample = node
    ? nodesStore.getDefinition(node.data.nodeType)?.sampleOutput
    : null;
  return sample ? { value: sample, contract: null, source: 'sample' } : null;
}

// Predecesores INMEDIATOS de un paso, según las aristas del lienzo.
function directPredecessors(id) {
  return edges.value.filter(e => e.target === id).map(e => e.source);
}

// TODOS los ancestros de un paso, del más cercano al más lejano. El orden
// importa: el panel de entrada ofrece primero lo que de verdad lo alimenta.
function ancestorsOf(id) {
  const seen = new Set();
  const ordered = [];
  let frontier = directPredecessors(id);
  while (frontier.length) {
    const next = [];
    frontier.forEach(current => {
      if (seen.has(current) || current === id) return;
      seen.add(current);
      const node = nodeById(current);
      if (node) ordered.push(node);
      next.push(...directPredecessors(current));
    });
    frontier = next;
  }
  return ordered;
}

const detailPrevious = computed(() =>
  detailId.value ? ancestorsOf(detailId.value) : []
);

const detailDirectPrevious = computed(() => {
  if (!detailId.value) return null;
  return directPredecessors(detailId.value)[0] ?? null;
});

function reachableFromLoop(loopId) {
  const seen = new Set();
  const queue = edges.value
    .filter(e => e.source === loopId && e.sourceHandle === 'loop')
    .map(e => e.target);
  while (queue.length) {
    const current = queue.shift();
    // Se para al volver al propio bucle: la arista de vuelta giraría en redondo.
    if (current && current !== loopId && !seen.has(current)) {
      seen.add(current);
      queue.push(
        ...edges.value.filter(e => e.source === current).map(e => e.target)
      );
    }
  }
  return seen;
}

// BUCLE que encierra al paso abierto: se sigue hacia atrás por el puerto
// 'loop'. Dentro de un bucle el elemento en curso se lee `{{item.*}}`, NO
// `{{node.<id>.output.*}}`, que procesaría siempre el primer elemento.
const detailLoopNode = computed(() => {
  if (!detailId.value) return null;
  const loops = nodes.value.filter(n => n.data.nodeType === 'logic.loop');
  return (
    loops.find(loop => reachableFromLoop(loop.id).has(detailId.value)) ?? null
  );
});

// Vecinos para navegar sin cerrar la vista: primero por las aristas, y si no
// hay, por el orden del lienzo.
const detailPrevNode = computed(() => {
  if (!detailId.value) return null;
  const direct = directPredecessors(detailId.value)[0];
  if (direct) return nodeById(direct);
  const index = nodes.value.findIndex(n => n.id === detailId.value);
  return index > 0 ? nodes.value[index - 1] : null;
});

const detailNextNode = computed(() => {
  if (!detailId.value) return null;
  const next = edges.value.find(e => e.source === detailId.value)?.target;
  if (next) return nodeById(next);
  const index = nodes.value.findIndex(n => n.id === detailId.value);
  return index >= 0 && index < nodes.value.length - 1
    ? nodes.value[index + 1]
    : null;
});

// Doble clic abre el detalle; el clic simple sigue seleccionando en el lienzo.
function openDetail(id) {
  selectedId.value = id;
  detailId.value = id;
}

function navigateDetail(id) {
  selectedId.value = id;
  detailId.value = id;
}

// Guarda la salida de una prueba junto a SU contrato: es lo que decide si
// `output` es un elemento y qué campos van a `.meta.*`.
function rememberOutput(nodeId, result) {
  if (!result || result.error) return;
  outputs.value = {
    ...outputs.value,
    [nodeId]: {
      value: result.output,
      contract: result.outputContract ?? null,
      source: 'test',
    },
  };
}

// Prueba de un paso previo lanzada desde el panel de entrada, para poblarlo.
async function testPrevious(nodeId) {
  // `save` se define más abajo porque necesita el grafo completo (notas incluidas).
  // eslint-disable-next-line no-use-before-define
  await save();
  const result = await flowsStore.runNode(flowId.value, nodeId);
  rememberOutput(nodeId, result);
}

const nodeTypes = { jabvox: FlowNode };

const isActive = computed(() => flow.value?.status === 'active');
const statusStyle = computed(() => flowStatusStyle(flow.value?.status));

// Id estable y legible: aparece en las referencias `{{node.<id>.output}}`.
// `taken` permite pegar varios pasos de golpe sin que choquen entre sí.
function nextId(type, taken) {
  const base = type.split('.').pop();
  const used = taken ?? new Set(nodes.value.map(n => n.id));
  let index = 1;
  while (used.has(`${base}${index}`)) index += 1;
  return `${base}${index}`;
}

function addNode(type, position) {
  const definition = nodesStore.getDefinition(type);
  if (!definition) return;
  nodes.value.push({
    id: nextId(type),
    type: 'jabvox',
    position: position || { x: 120, y: 120 },
    data: { nodeType: type, label: definition.label, params: {} },
  });
}

function onDrop(event) {
  const type = event.dataTransfer.getData('application/jabvox-flow-node');
  if (!type) return;
  const bounds = vueFlowRef.value.getBoundingClientRect();
  addNode(
    type,
    project({
      x: event.clientX - bounds.left,
      y: event.clientY - bounds.top,
    })
  );
}

onConnect(params =>
  addEdges([{ ...params, markerEnd: MarkerType.ArrowClosed }])
);

function updateParams(params) {
  const node = selectedNode.value;
  if (node) node.data = { ...node.data, params };
}

function deleteNode() {
  const id = selectedId.value;
  nodes.value = nodes.value.filter(n => n.id !== id);
  edges.value = edges.value.filter(e => e.source !== id && e.target !== id);
  selectedId.value = null;
  detailId.value = null;
}

// ---- §1 NOTAS ADHESIVAS ---------------------------------------------------
//
// Son SOLO texto y SOLO visuales: van detrás de los pasos y el motor no las
// mira (viajan en la clave `notes`, aparte de `nodes`/`edges`).

const notes = ref([]);
const selectedNoteId = ref(null);

// La capa de notas no es hija de <VueFlow>: su slot por defecto se renderiza
// DESPUÉS del viewport y quedaría por encima de los pasos. Se monta como
// hermano anterior y se le aplica a mano la misma transformación del lienzo.
// Viewport usable: `<Background>` divide por el zoom sin red de seguridad y
// pintaría `NaN` en los atributos SVG si llegara un valor no numérico.
const viewportReady = computed(() => {
  const { x, y, zoom } = viewport.value ?? {};
  return (
    Number.isFinite(x) &&
    Number.isFinite(y) &&
    Number.isFinite(zoom) &&
    zoom > 0
  );
});

const notesTransform = computed(() => {
  if (!viewportReady.value) return 'translate(0px, 0px) scale(1)';
  return `translate(${viewport.value.x}px, ${viewport.value.y}px) scale(${viewport.value.zoom})`;
});

// Centro del lienzo VISIBLE, en coordenadas del grafo.
function centerOfViewport() {
  const bounds = vueFlowRef.value?.getBoundingClientRect();
  if (!bounds) return { x: 80, y: 80 };
  const point = project({ x: bounds.width / 2, y: bounds.height / 2 });
  return {
    x: Math.round(point.x - NOTE_DEFAULTS.width / 2),
    y: Math.round(point.y - NOTE_DEFAULTS.height / 2),
  };
}

function selectNote(id) {
  selectedNoteId.value = id;
  // Seleccionar una nota deselecciona los pasos: las acciones de la barra
  // (borrar, copiar) tienen que saber sobre qué actúan.
  selectedId.value = null;
  removeSelectedElements();
}

function addNote(position) {
  const taken = new Set(notes.value.map(n => n.id));
  const id = nextNoteId(taken);
  // Sin posición: se centra en lo que se está viendo, no en el origen del lienzo.
  // La cascada evita que dos notas nazcan superpuestas (arrastrar una movía dos).
  const at = freeNotePosition(position || centerOfViewport(), notes.value);
  notes.value = [
    ...notes.value,
    {
      id,
      position: at,
      width: NOTE_DEFAULTS.width,
      height: NOTE_DEFAULTS.height,
      color: NOTE_DEFAULTS.color,
      text: '',
    },
  ];
  selectNote(id);
}

function updateNote(next) {
  notes.value = notes.value.map(n => (n.id === next.id ? next : n));
}

function deleteNote(id) {
  notes.value = notes.value.filter(n => n.id !== id);
  if (selectedNoteId.value === id) selectedNoteId.value = null;
}

function duplicateNote(id) {
  const source = notes.value.find(n => n.id === id);
  if (!source) return;
  const taken = new Set(notes.value.map(n => n.id));
  const copy = {
    ...source,
    id: nextNoteId(taken),
    position: freeNotePosition(
      { x: source.position.x + 32, y: source.position.y + 32 },
      notes.value
    ),
  };
  notes.value = [...notes.value, copy];
  selectNote(copy.id);
}

// ---- §3 COPIAR / CORTAR / PEGAR ------------------------------------------

// Respaldo en memoria por si `navigator.clipboard` está restringido.
const internalClipboard = ref('');

// Posición del último clic en el lienzo: es donde se pega.
const lastPointer = ref(null);

// Escribiendo en un campo, los atajos son del campo, no del lienzo.
function isTextField(el) {
  if (!el) return false;
  const tag = el.tagName;
  return (
    tag === 'INPUT' ||
    tag === 'TEXTAREA' ||
    tag === 'SELECT' ||
    el.isContentEditable === true
  );
}

// Se mira el target Y el elemento con foco: escribiendo en una nota, Ctrl+C es
// del texto, no de los pasos, y el target no siempre es el campo.
function isEditingText(target) {
  return isTextField(target) || isTextField(document.activeElement);
}

// Mensaje del fallo al interpretar lo pegado. Las claves se nombran una a una:
// construirlas por plantilla las esconde del extractor de traducciones.
function parseErrorMessage(kind) {
  switch (kind) {
    case 'malformed-json':
      return t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.PARSE_MALFORMED_JSON');
    case 'not-an-object':
      return t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.PARSE_NOT_AN_OBJECT');
    case 'missing-fields':
      return t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.PARSE_MISSING_FIELDS');
    case 'no-nodes':
      return t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.PARSE_NO_NODES');
    case 'n8n-format':
      return t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.PARSE_N8N_FORMAT');
    default:
      // 'empty': el usuario no pegó nada, no hay nada que decir.
      return null;
  }
}

/**
 * AVISA de lo que no sobrevivió al pegado. Antes se descartaba en silencio y el
 * usuario perdía pasos y conexiones sin explicación.
 */
function reportPasteLosses(prepared, parsed) {
  const warnings = [];
  const dropped = [...prepared.droppedEdges, ...(parsed.orphanEdges ?? [])];
  if (dropped.length) {
    warnings.push(
      t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.DROPPED_EDGES', {
        count: dropped.length,
        detail: dropped
          .slice(0, 3)
          .map(e => `${e.source} → ${e.target}`)
          .join('; '),
      })
    );
  }
  if (prepared.brokenCount) {
    warnings.push(
      t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.BROKEN_REFS', {
        count: prepared.brokenCount,
        detail: [...new Set([...prepared.brokenRefs.values()].flat())]
          .slice(0, 3)
          .join(', '),
      })
    );
  }
  if (parsed.unknownTypes?.length) {
    warnings.push(
      t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.SKIPPED_UNKNOWN', {
        types: parsed.unknownTypes.slice(0, 3).join(', '),
      })
    );
  }
  const total = prepared.nodes.length + prepared.notes.length;
  useAlert(
    warnings.length
      ? `${t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.PASTED', { count: total })} ${warnings.join(' ')}`
      : t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.PASTED', { count: total })
  );
}

// Lo que se copiaría ahora: la selección múltiple de Vue Flow, y si no hay,
// el paso marcado con el clic simple.
function selectionForClipboard() {
  const selected = getSelectedNodes.value ?? [];
  const ids = new Set(selected.map(n => n.id));
  // Sin selección múltiple vale el paso del clic simple.
  if (!ids.size && selectedId.value) ids.add(selectedId.value);
  const pickedNotes = selectedNoteId.value
    ? notes.value.filter(n => n.id === selectedNoteId.value)
    : [];
  return {
    nodes: nodes.value.filter(n => ids.has(n.id)),
    notes: pickedNotes,
  };
}

async function copySelection({ cut = false } = {}) {
  const picked = selectionForClipboard();
  if (!picked.nodes.length && !picked.notes.length) {
    useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.NOTHING_SELECTED'));
    return;
  }

  const text = serializeToText(picked.nodes, edges.value, picked.notes);
  const written = await writeClipboardText(text);
  // Respaldo interno: si el navegador niega el portapapeles, pegar dentro del
  // propio editor sigue funcionando en esta pestaña.
  internalClipboard.value = text;

  if (cut) {
    const ids = new Set(picked.nodes.map(n => n.id));
    nodes.value = nodes.value.filter(n => !ids.has(n.id));
    edges.value = edges.value.filter(
      e => !ids.has(e.source) && !ids.has(e.target)
    );
    const noteIds = new Set(picked.notes.map(n => n.id));
    notes.value = notes.value.filter(n => !noteIds.has(n.id));
    selectedId.value = null;
    selectedNoteId.value = null;
    detailId.value = null;
  }

  const count = picked.nodes.length + picked.notes.length;
  const done = cut
    ? t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.CUT', { count })
    : t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.COPIED', { count });
  const warn = written
    ? ''
    : ` ${t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.LOCAL_ONLY')}`;
  useAlert(done + warn);
}

function rememberPointer(event) {
  const bounds = vueFlowRef.value?.getBoundingClientRect();
  if (!bounds) return;
  lastPointer.value = project({
    x: event.clientX - bounds.left,
    y: event.clientY - bounds.top,
  });
}

/**
 * Pega el texto dado. Devuelve false si no había nada válido, para que quien
 * llama pueda recurrir al respaldo interno.
 */
function pasteText(text, { at } = {}) {
  const known = new Set(nodesStore.definitions.map(d => d.type));
  const parsed = parseFlowText(text, known);
  if (!parsed.ok) {
    const message = parseErrorMessage(parsed.kind);
    if (message) useAlert(message);
    return false;
  }

  // Los tipos que este catálogo no conoce no se pegan: un paso sin definición
  // no se puede dibujar ni configurar.
  const unknown = new Set(parsed.unknownTypes);
  const usable = parsed.payload.nodes.filter(
    n => !unknown.has(n.data.nodeType)
  );
  if (!usable.length && !parsed.payload.notes.length) {
    useAlert(
      t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.ALL_UNKNOWN', {
        types: parsed.unknownTypes.join(', '),
      })
    );
    return true;
  }

  const usableIds = new Set(usable.map(n => n.id));
  const prepared = preparePaste(
    {
      ...parsed.payload,
      nodes: usable,
      edges: parsed.payload.edges.filter(
        e => usableIds.has(e.source) && usableIds.has(e.target)
      ),
    },
    {
      existingIds: new Set(nodes.value.map(n => n.id)),
      existingLabels: new Set(nodes.value.map(n => n.data.label)),
      existingNoteIds: new Set(notes.value.map(n => n.id)),
      makeId: (type, taken) => nextId(type, taken),
      makeNoteId: taken => nextNoteId(taken),
      ...(at ? { at } : {}),
    }
  );

  nodes.value = [
    ...nodes.value,
    ...prepared.nodes.map(n => ({
      id: n.id,
      type: 'jabvox',
      position: n.position,
      data: n.data,
      selected: true,
    })),
  ];
  edges.value = [
    ...edges.value,
    ...prepared.edges.map(e => ({ ...e, markerEnd: MarkerType.ArrowClosed })),
  ];
  notes.value = [...notes.value, ...prepared.notes.map(n => normalizeNote(n))];

  // Lo pegado queda seleccionado: mover el bloque entero es lo siguiente que
  // se quiere hacer.
  removeSelectedElements();
  const fresh = prepared.nodes.map(n => findNode(n.id)).filter(Boolean);
  if (fresh.length) addSelectedNodes(fresh);
  selectedNoteId.value = prepared.notes[0]?.id ?? null;

  reportPasteLosses(prepared, parsed);
  return true;
}

// El evento `paste` del navegador trae el texto SIN pedir permiso: es la vía
// fiable. El botón de la barra usa `readText`, que suele estar restringido.
function onPaste(event) {
  if (isEditingText(event.target)) return;
  const text = event.clipboardData?.getData('text/plain');
  if (!text) return;
  event.preventDefault();
  pasteText(text, { at: lastPointer.value ?? undefined });
}

async function pasteFromButton() {
  const text = (await readClipboardText()) || internalClipboard.value;
  if (!text) {
    useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.READ_DENIED'));
    return;
  }
  pasteText(text, { at: lastPointer.value ?? undefined });
}

// Duplicar sin pasar por el portapapeles del sistema: es lo que espera Ctrl+D.
function duplicateSelection() {
  const picked = selectionForClipboard();
  if (!picked.nodes.length && !picked.notes.length) return;
  pasteText(serializeToText(picked.nodes, edges.value, picked.notes));
}

// Borrar TODO lo seleccionado: pasos de la selección múltiple y la nota activa.
function deleteSelection() {
  const selected = getSelectedNodes.value ?? [];
  const ids = new Set(selected.map(n => n.id));
  if (selectedId.value) ids.add(selectedId.value);
  if (ids.size) {
    nodes.value = nodes.value.filter(n => !ids.has(n.id));
    edges.value = edges.value.filter(
      e => !ids.has(e.source) && !ids.has(e.target)
    );
    selectedId.value = null;
    detailId.value = null;
  }
  if (selectedNoteId.value) deleteNote(selectedNoteId.value);
}

function onKeydown(event) {
  if (isEditingText(event.target)) return;
  const mod = event.metaKey || event.ctrlKey;
  const key = event.key.toLowerCase();

  if (mod && key === 'c') {
    event.preventDefault();
    copySelection();
    return;
  }
  if (mod && key === 'x') {
    event.preventDefault();
    copySelection({ cut: true });
    return;
  }
  if (mod && key === 'd') {
    // Duplicar: copiar y pegar de golpe, junto al original.
    event.preventDefault();
    duplicateSelection();
    return;
  }
  if (mod && key === 'a') {
    event.preventDefault();
    addSelectedNodes(nodes.value.map(n => findNode(n.id)).filter(Boolean));
    return;
  }
  if (key === 'delete' || key === 'backspace') {
    event.preventDefault();
    deleteSelection();
  }
}

// El grafo se envía tal cual lo dibuja el lienzo: el backend lo guarda entero y
// solo el editor lo interpreta.
function currentGraph() {
  return {
    nodes: nodes.value.map(n => ({
      id: n.id,
      type: n.data.nodeType,
      position: n.position,
      params: n.data.params || {},
      data: n.data,
    })),
    edges: edges.value.map(e => ({
      id: e.id,
      source: e.source,
      target: e.target,
      sourceHandle: e.sourceHandle,
    })),
    // Notas adhesivas: decoración. El backend las guarda y el motor las ignora.
    notes: notes.value.map(serializeNote),
  };
}

// ---- §4 AUTOGUARDADO -----------------------------------------------------
//
// El backend crea una versión en CADA `PUT /versions`, así que el autoguardado
// se agrupa por ventana de tiempo (ver `useFlowAutosave`): como mucho una
// versión por minuto de edición continua. El guardado manual no espera.

const scheduler = createAutosaveScheduler();
// 'idle' | 'pending' | 'saving' | 'saved' | 'error'
const autosaveState = ref('idle');
const lastSavedAt = ref(null);
const autosaveConflict = ref(false);
let autosaveTimer = null;

// Versión que el editor cree tener cargada. El backend NO ofrece control de
// concurrencia (no hay `expectedVersion` ni 409), así que el conflicto se
// DETECTA aquí comparando antes de pisar, en vez de sobrescribir en silencio.
const knownVersion = ref(null);

// En la barra basta la HORA: la fecha completa no cabe y el guardado siempre es
// de hoy. La fecha entera queda en el título, para el guardado de otro día.
const lastSavedLabel = computed(() => {
  if (!lastSavedAt.value) return null;
  const date = new Date(lastSavedAt.value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' });
});

const lastSavedTitle = computed(() =>
  lastSavedAt.value ? formatDateTime(lastSavedAt.value) : ''
);

function clearAutosaveTimer() {
  if (autosaveTimer) {
    clearTimeout(autosaveTimer);
    autosaveTimer = null;
  }
}

// Escribiendo en una nota o en un campo NO se autoguarda: se guardaría a medias
// y el repintado podría robar el foco.
function editingText() {
  return isTextField(document.activeElement);
}

/**
 * ¿Cambió el flujo por fuera desde que lo cargamos? Sin control de concurrencia
 * en el backend, se comprueba pidiendo la versión actual antes de guardar.
 */
async function remoteChanged() {
  if (knownVersion.value === null) return false;
  try {
    // API directa, no el store: esta comprobación no debe pisar la lista que
    // está mostrando el panel de versiones.
    const { data } = await flowsAPI.listVersions(flowId.value);
    const top = data?.[0]?.version ?? null;
    return top !== null && top > knownVersion.value;
  } catch {
    // No se pudo comprobar: no se bloquea el guardado por ello.
    return false;
  }
}

/**
 * Guarda el lienzo como versión nueva y deja el autoguardado al día. Lo usan
 * el botón Guardar, el autoguardado y la activación: si alguno no actualizara
 * el planificador, el autoguardado reenviaría lo mismo al vencer la ventana.
 */
async function persistGraph() {
  const graph = currentGraph();
  const saved = await flowsStore.saveVersion(flowId.value, graph);
  knownVersion.value = saved?.currentVersion?.version ?? knownVersion.value;
  scheduler.markSaved(graphFingerprint(graph), Date.now());
  lastSavedAt.value = new Date().toISOString();
  autosaveState.value = 'saved';
  autosaveConflict.value = false;
  versionsRef.value?.load();
  return saved;
}

// Se reprograma en cada cambio: el planificador decide si ya toca guardar o
// cuánto falta.
// Referencia adelantada: `scheduleAutosave` y `autosaveNow` se llaman entre sí.
let autosaveNowRef;

function scheduleAutosave() {
  clearAutosaveTimer();
  const delay = scheduler.nextCheckDelay(Date.now());
  if (delay === null) return;
  autosaveState.value = 'pending';
  autosaveTimer = setTimeout(() => {
    autosaveTimer = null;
    if (scheduler.shouldSave(Date.now())) autosaveNowRef();
    else scheduleAutosave();
  }, delay);
}

async function autosaveNow() {
  // Escribiendo en un campo se reprograma: guardar ahora robaría el foco.
  if (editingText()) {
    scheduleAutosave();
    return;
  }
  autosaveState.value = 'saving';
  try {
    if (await remoteChanged()) {
      // Otra pestaña o usuario avanzó el flujo: NO se pisa en silencio.
      autosaveConflict.value = true;
      autosaveState.value = 'error';
      return;
    }
    await persistGraph();
  } catch (e) {
    issues.value = graphIssues(e) || [];
    autosaveState.value = 'error';
  }
}
autosaveNowRef = autosaveNow;

async function load() {
  loading.value = true;
  await nodesStore.load();
  const data = await flowsStore.fetchOne(flowId.value);
  const graph = data?.currentVersion?.graph;
  if (graph) {
    nodes.value = (graph.nodes || []).map(n => ({
      id: n.id,
      type: 'jabvox',
      position: n.position || { x: 100, y: 100 },
      data: n.data || { nodeType: n.type, params: n.params || {} },
    }));
    edges.value = (graph.edges || []).map(e => ({
      ...e,
      markerEnd: MarkerType.ArrowClosed,
    }));
    // Un grafo guardado antes de que existieran las notas no trae `notes`.
    notes.value = (graph.notes || []).map(normalizeNote);
  }
  loading.value = false;
  // Referencia del autoguardado: lo recién cargado ES lo guardado.
  knownVersion.value = data?.currentVersion?.version ?? null;
  lastSavedAt.value = data?.currentVersion?.createdAt ?? null;
  autosaveConflict.value = false;
  autosaveState.value = 'idle';
  // SIN sello de tiempo: la ventana de 60 s cuenta desde el primer guardado
  // real, no desde que se abre el editor. Si no, el primer cambio esperaría un
  // minuto entero para persistirse.
  scheduler.markSaved(graphFingerprint(currentGraph()));
}

// Recarga el lienzo tras restaurar una versión: el backend ya creó la versión
// nueva, aquí solo se refleja.
async function reloadAfterRestore() {
  clearAutosaveTimer();
  await load();
  useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORED'));
}

async function save() {
  clearAutosaveTimer();
  try {
    await persistGraph();
    issues.value = [];
    useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.SAVED'));
  } catch (e) {
    issues.value = graphIssues(e) || [];
    showIssues.value = true;
    autosaveState.value = 'error';
    useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.ERRORS.SAVE'));
  }
}

async function validate() {
  validating.value = true;
  try {
    const result = await flowsStore.validate(flowId.value, currentGraph());
    issues.value = result.issues;
    showIssues.value = true;
    if (result.valid) {
      useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NO_ISSUES'));
    }
  } finally {
    validating.value = false;
  }
}

// Activar exige que el grafo pase la validación estricta del backend: se guarda
// antes para que valide justo lo que se ve en el lienzo.
async function toggleActive() {
  const next = flow.value?.status === 'active' ? 'paused' : 'active';
  clearAutosaveTimer();
  try {
    if (next === 'active') await persistGraph();
    await flowsStore.setStatus(flowId.value, next);
    issues.value = [];
  } catch (e) {
    issues.value = graphIssues(e) || [];
    showIssues.value = true;
    useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.ACTIVATE_BLOCKED'));
  }
}

async function runFlow() {
  running.value = true;
  try {
    await save();
    await flowsStore.run(flowId.value);
    useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.RUN'));
    historyRef.value?.load();
  } finally {
    running.value = false;
  }
}

async function testStep() {
  testing.value = true;
  try {
    await save();
    testResult.value = await flowsStore.runNode(flowId.value, selectedId.value);
    rememberOutput(selectedId.value, testResult.value);
  } finally {
    testing.value = false;
  }
}

async function runFromStep() {
  await save();
  await flowsStore.runFrom(flowId.value, selectedId.value);
  useAlert(t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.RUN_FROM'));
  historyRef.value?.load();
}

// Cambiar de paso descarta la salida de la prueba anterior: era de otro paso.
watch(selectedId, () => {
  testResult.value = null;
});

// Vigilancia del autoguardado. `deep` es obligatorio (Vue Flow muta los objetos
// en sitio), pero la HUELLA es lo que decide: sin ella cada render arrastraría
// un guardado. Mientras carga o hay conflicto no se programa nada.
watch(
  [nodes, edges, notes],
  () => {
    if (loading.value || autosaveConflict.value) return;
    const changed = scheduler.noteChange(
      graphFingerprint(currentGraph()),
      Date.now()
    );
    if (changed) scheduleAutosave();
  },
  { deep: true }
);

// Los atajos van en `window`: el lienzo no siempre tiene el foco cuando el
// usuario pulsa Ctrl+C tras hacer clic en un paso.
onMounted(() => {
  load();
  window.addEventListener('keydown', onKeydown);
  window.addEventListener('paste', onPaste);
});

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown);
  window.removeEventListener('paste', onPaste);
  clearAutosaveTimer();
});
</script>

<template>
  <!-- `w-full min-w-0` es lo que le da el ancho: el <main> del dashboard es un
  flex y sin ellos el editor se encogía al tamaño de su contenido. -->
  <div class="flex h-full w-full min-h-0 min-w-0 flex-col bg-n-background">
    <!-- §2 Barra superior: identidad del flujo a la izquierda, acciones a la derecha. -->
    <header
      class="flex shrink-0 items-center gap-3 border-b border-n-weak bg-n-solid-1 px-3 py-2.5"
    >
      <button
        type="button"
        class="flex size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.BACK')"
        @click="router.push({ name: 'jabvox_advanced_automations_settings' })"
      >
        <span class="i-lucide-arrow-left size-4" />
      </button>

      <span
        class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-brand"
      >
        <span class="i-lucide-workflow size-4" />
      </span>

      <div class="flex min-w-0 items-center gap-2">
        <h2 class="truncate text-sm font-semibold text-n-slate-12">
          {{ flow?.name || '…' }}
        </h2>
        <span
          v-if="flow?.status"
          class="inline-flex shrink-0 items-center gap-1.5 rounded-md px-1.5 py-0.5 text-[10px] font-medium"
          :class="statusStyle.chip"
        >
          <span class="size-1.5 rounded-full" :class="statusStyle.dot" />
          {{ t(`JABVOX_ADVANCED_AUTOMATIONS.STATUS.${flow.status}`) }}
        </span>
      </div>

      <!-- Estado del autoguardado, junto al nombre: es información, no un botón. -->
      <p
        class="ml-3 hidden min-w-0 items-center gap-1.5 text-xs text-n-slate-11 lg:flex"
        :class="{ 'text-n-ruby-11': autosaveState === 'error' }"
        :title="lastSavedTitle"
      >
        <span
          v-if="autosaveState === 'saving'"
          class="i-lucide-loader-circle size-3.5 shrink-0 animate-spin"
        />
        <span
          v-else-if="autosaveState === 'pending'"
          class="i-lucide-clock size-3.5 shrink-0"
        />
        <span
          v-else-if="autosaveState === 'error'"
          class="i-lucide-circle-alert size-3.5 shrink-0"
        />
        <span
          v-else-if="autosaveState === 'saved'"
          class="i-lucide-cloud-check size-3.5 shrink-0"
        />
        <span class="truncate">
          <template v-if="autosaveState === 'saving'">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.SAVING') }}
          </template>
          <template v-else-if="autosaveState === 'pending'">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.PENDING') }}
          </template>
          <template v-else-if="autosaveConflict">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.CONFLICT') }}
          </template>
          <template v-else-if="autosaveState === 'error'">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.ERROR') }}
          </template>
          <template v-else-if="lastSavedLabel">
            {{
              t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.SAVED_AT', {
                time: lastSavedLabel,
              })
            }}
          </template>
        </span>
      </p>

      <div class="ml-auto flex shrink-0 items-center gap-2">
        <button
          type="button"
          class="hidden h-8 items-center gap-1.5 rounded-lg px-3 text-sm font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2 disabled:opacity-50 sm:inline-flex"
          :disabled="validating"
          @click="validate"
        >
          <span
            :class="
              validating
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-shield-check'
            "
            class="size-4"
          />
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.VALIDATE') }}
        </button>

        <button
          type="button"
          class="inline-flex h-8 items-center gap-1.5 rounded-lg px-3 text-sm font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2 disabled:opacity-50"
          :disabled="running"
          @click="runFlow"
        >
          <span
            :class="
              running ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-play'
            "
            class="size-4"
          />
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.RUN') }}
        </button>

        <button
          type="button"
          class="inline-flex h-8 items-center gap-1.5 rounded-lg bg-n-brand px-3 text-sm font-medium text-white transition-all hover:brightness-110 disabled:opacity-50"
          :disabled="flowsStore.saving"
          @click="save"
        >
          <span
            :class="
              flowsStore.saving
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-save'
            "
            class="size-4"
          />
          {{
            flowsStore.saving
              ? t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.SAVING')
              : t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.SAVE')
          }}
        </button>

        <!-- Activar/desactivar vive en el menú ⋮ del boceto, con lo destructivo. -->
        <div class="relative">
          <button
            type="button"
            class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
            @click="menuOpen = !menuOpen"
          >
            <span class="i-lucide-more-vertical size-4" />
          </button>

          <div
            v-if="menuOpen"
            class="absolute right-0 top-10 z-20 w-56 overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 py-1 shadow-lg"
          >
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-2"
              @click="
                menuOpen = false;
                toggleActive();
              "
            >
              <span
                :class="isActive ? 'i-lucide-pause' : 'i-lucide-circle-play'"
                class="size-4 shrink-0"
                :style="{ color: isActive ? undefined : '#186d6a' }"
              />
              {{
                isActive
                  ? t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.DEACTIVATE')
                  : t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.ACTIVATE')
              }}
            </button>
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-2 sm:hidden"
              @click="
                menuOpen = false;
                validate();
              "
            >
              <span class="i-lucide-shield-check size-4 shrink-0" />
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.VALIDATE') }}
            </button>
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-2"
              @click="
                menuOpen = false;
                versionsOpen = !versionsOpen;
              "
            >
              <span class="i-lucide-git-commit-vertical size-4 shrink-0" />
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.TITLE') }}
            </button>
          </div>
        </div>
      </div>
    </header>

    <!-- CONFLICTO: el flujo avanzó por fuera. El autoguardado se detiene para no
    pisar lo que hizo otra pestaña u otro usuario. -->
    <div
      v-if="autosaveConflict"
      class="shrink-0 border-b border-n-amber-8 bg-n-amber-3"
    >
      <div class="flex items-start gap-2 px-4 py-2.5">
        <span
          class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
        />
        <div class="min-w-0 flex-1">
          <p class="text-xs font-semibold text-n-amber-11">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.CONFLICT') }}
          </p>
          <p class="mt-0.5 text-xs leading-relaxed text-n-amber-11">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.CONFLICT_HELP') }}
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 rounded-lg px-2 py-1 text-xs font-medium text-n-amber-11 transition-colors hover:bg-n-amber-4"
          @click="load()"
        >
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.CONFLICT_RELOAD') }}
        </button>
        <button
          type="button"
          class="shrink-0 rounded-lg px-2 py-1 text-xs font-medium text-n-amber-11 transition-colors hover:bg-n-amber-4"
          @click="
            autosaveConflict = false;
            save();
          "
        >
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.AUTOSAVE.CONFLICT_OVERWRITE') }}
        </button>
      </div>
    </div>

    <!-- Los problemas del backend son la razón por la que no se puede activar. -->
    <div
      v-if="issues.length && showIssues"
      class="shrink-0 border-b border-n-ruby-8 bg-n-ruby-3"
    >
      <div class="flex items-start gap-2 px-4 py-2.5">
        <span
          class="i-lucide-circle-alert mt-0.5 size-4 shrink-0 text-n-ruby-11"
        />
        <div class="min-w-0 flex-1">
          <p class="text-xs font-semibold text-n-ruby-11">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.ISSUES') }}
            ({{ issues.length }})
          </p>
          <ul class="mt-1 max-h-28 space-y-0.5 overflow-y-auto">
            <li
              v-for="(issue, index) in issues"
              :key="index"
              class="text-xs leading-relaxed text-n-ruby-11"
            >
              <strong v-if="issue.nodeLabel">{{ issue.nodeLabel }}:</strong>
              {{ issue.message }}
            </li>
          </ul>
        </div>
        <button
          type="button"
          class="flex size-6 shrink-0 items-center justify-center rounded-md text-n-ruby-11 transition-colors hover:bg-n-ruby-4"
          @click="showIssues = false"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
    </div>

    <div class="flex min-h-0 flex-1">
      <NodePalette class="hidden md:flex" @add="addNode($event)" />

      <div
        class="relative min-w-0 flex-1"
        @drop="onDrop"
        @dragover.prevent
        @pointerdown="rememberPointer"
      >
        <!-- §1 CAPA DE NOTAS: hermano ANTERIOR al lienzo y con z-index 0, así
        queda DETRÁS de los pasos (Vue Flow los pinta en un
        .vue-flow__transformationpane con z-index 2). `pointer-events-none` deja
        pasar al lienzo los clics de panear; cada nota los recupera. -->
        <div
          class="jf-notes-layer pointer-events-none absolute inset-0 overflow-hidden"
          aria-hidden="false"
        >
          <div
            class="absolute left-0 top-0 origin-top-left"
            :style="{ transform: notesTransform }"
          >
            <StickyNote
              v-for="note in notes"
              :key="note.id"
              :note="note"
              :selected="note.id === selectedNoteId"
              :zoom="viewport.zoom"
              @select="selectNote"
              @update="updateNote"
              @delete="deleteNote"
              @duplicate="duplicateNote"
            />
          </div>
        </div>

        <VueFlow
          :id="CANVAS_ID"
          v-model:nodes="nodes"
          v-model:edges="edges"
          :node-types="nodeTypes"
          fit-view-on-init
          multi-selection-key-code="Shift"
          selection-key-code="Shift"
          snap-to-grid
          :delete-key-code="null"
          :connection-radius="28"
          :snap-grid="[16, 16]"
          :default-edge-options="{
            type: 'smoothstep',
            animated: false,
            style: { strokeWidth: 2 },
            markerEnd: MarkerType.ArrowClosed,
          }"
          class="jf-canvas jf-canvas-layer"
          @node-click="
            selectedId = $event.node.id;
            selectedNoteId = null;
          "
          @node-double-click="openDetail($event.node.id)"
          @pane-click="
            selectedId = null;
            selectedNoteId = null;
            menuOpen = false;
          "
        >
          <Background
            v-if="viewportReady"
            :gap="16"
            :size="1.4"
            pattern-color="rgb(var(--slate-6))"
          />
          <!-- §2 Solo los controles, abajo a la izquierda como en n8n. Los
          coloca `.vue-flow__panel` del CSS importado arriba, no clases nuestras. -->
          <Controls position="bottom-left" :show-interactive="false" />
        </VueFlow>

        <!-- Barra del lienzo: notas y portapapeles, abajo a la derecha. -->
        <div
          class="absolute bottom-4 right-4 z-[2] flex items-center gap-1 rounded-xl border border-n-weak bg-n-solid-1/95 p-1 shadow-sm backdrop-blur"
        >
          <button
            type="button"
            class="flex h-8 items-center gap-1.5 rounded-lg px-2.5 text-xs font-medium text-n-slate-12 transition-colors hover:bg-n-alpha-2"
            :title="t('JABVOX_ADVANCED_AUTOMATIONS.NOTES.ADD_HINT')"
            @click="addNote()"
          >
            <span class="i-lucide-sticky-note size-4" />
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.NOTES.ADD') }}
          </button>
          <span class="mx-0.5 h-5 w-px bg-n-weak" />
          <button
            type="button"
            class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
            :title="t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.COPY_HINT')"
            @click="copySelection()"
          >
            <span class="i-lucide-copy size-4" />
          </button>
          <button
            type="button"
            class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
            :title="t('JABVOX_ADVANCED_AUTOMATIONS.CLIPBOARD.PASTE_HINT')"
            @click="pasteFromButton"
          >
            <span class="i-lucide-clipboard-paste size-4" />
          </button>
        </div>

        <div
          v-if="loading"
          class="absolute inset-0 flex items-center justify-center bg-n-background"
        >
          <span class="flex items-center gap-2 text-sm text-n-slate-11">
            <span class="i-lucide-loader-circle size-4 animate-spin" />
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.LOADING') }}
          </span>
        </div>

        <div
          v-else-if="!nodes.length && !notes.length"
          class="pointer-events-none absolute inset-0 z-[2] flex flex-col items-center justify-center gap-3 px-6 text-center"
        >
          <span
            class="flex size-14 items-center justify-center rounded-2xl bg-n-alpha-2"
          >
            <span class="i-lucide-workflow size-7 text-n-slate-10" />
          </span>
          <p class="max-w-xs text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.EMPTY_CANVAS') }}
          </p>
        </div>
      </div>

      <!-- Historial de versiones: panel lateral, se abre desde el menú ⋮. -->
      <VersionHistory
        v-if="versionsOpen"
        ref="versionsRef"
        :flow-id="flowId"
        @close="versionsOpen = false"
        @restored="reloadAfterRestore"
      />
    </div>

    <RunHistory ref="historyRef" :flow-id="flowId" />

    <!-- Detalle en tres columnas: entrada | configuración | salida. -->
    <NodeDetailView
      v-if="detailNode"
      :node="detailNode"
      :previous="detailPrevious"
      :direct-previous="detailDirectPrevious"
      :output-for="outputFor"
      :loop-node="detailLoopNode"
      :test-result="testResult"
      :testing="testing"
      :prev-node="detailPrevNode"
      :next-node="detailNextNode"
      @close="detailId = null"
      @navigate="navigateDetail"
      @update-params="updateParams"
      @test="testStep"
      @run-from="runFromStep"
      @run-previous="testPrevious"
      @delete="deleteNode"
    />
  </div>
</template>

<style scoped>
/* La capa de notas es el hermano ANTERIOR del lienzo, así que apilarlas bien es
   lo único que las mantiene DETRÁS de los pasos. No se deja a las clases de
   Tailwind: `.vue-flow` ya trae `z-index: 0` con la misma especificidad, y quién
   gana dependería del orden en que se carguen las hojas. */
.jf-notes-layer {
  z-index: 0;
}
.jf-canvas-layer {
  position: relative;
  z-index: 1;
  /* El fondo del lienzo taparía las notas: el patrón lo pinta <Background>. */
  background: transparent;
}

/* §3 CONEXIONES: reposo discreto, foco evidente. La punta de flecha es lo que
   deja clara la DIRECCIÓN, y se tiñe con el mismo color que el trazo. */
.jf-canvas :deep(.vue-flow__edge-path) {
  stroke: rgb(var(--slate-8));
  transition:
    stroke 120ms ease,
    stroke-width 120ms ease;
}
.jf-canvas :deep(.vue-flow__edge .vue-flow__edge-interaction) {
  /* Franja invisible más ancha que el trazo: acertar una conexión de 2px con el
     ratón es imposible, y sin esto seleccionarlas es un ejercicio de puntería. */
  stroke-width: 18;
}
.jf-canvas :deep(.vue-flow__edge:hover .vue-flow__edge-path) {
  stroke: rgb(var(--blue-9));
  stroke-width: 2.5;
}
.jf-canvas :deep(.vue-flow__edge.selected .vue-flow__edge-path) {
  stroke: rgb(var(--blue-10));
  stroke-width: 3;
}
.jf-canvas :deep(.vue-flow__edge.animated .vue-flow__edge-path) {
  stroke: rgb(var(--blue-9));
}
.jf-canvas :deep(.vue-flow__arrowhead polyline),
.jf-canvas :deep(.vue-flow__arrowhead path) {
  fill: rgb(var(--slate-8));
  stroke: rgb(var(--slate-8));
}
/* Conexión EN CURSO: discontinua y en color de marca, para distinguirla de las
   ya establecidas mientras se arrastra. */
.jf-canvas :deep(.vue-flow__connection-path) {
  stroke: rgb(var(--blue-9));
  stroke-width: 2.5;
  stroke-dasharray: 6 4;
}

/* Puertos: pequeños en reposo, crecen al acercarse para poder acertarlos. */
.jf-canvas :deep(.vue-flow__handle) {
  transition:
    transform 120ms ease,
    box-shadow 120ms ease;
}
.jf-canvas :deep(.vue-flow__node:hover .vue-flow__handle) {
  box-shadow: 0 0 0 3px rgb(var(--blue-4));
}
.jf-canvas :deep(.vue-flow__handle-valid) {
  box-shadow: 0 0 0 4px rgb(var(--teal-5));
}
.jf-canvas :deep(.vue-flow__handle-connecting) {
  box-shadow: 0 0 0 4px rgb(var(--ruby-5));
}

/* Selección por recuadro (Shift + arrastre). */
.jf-canvas :deep(.vue-flow__selection) {
  background: rgb(var(--blue-9) / 0.08);
  border: 1px dashed rgb(var(--blue-9));
  border-radius: 6px;
}
.jf-canvas :deep(.vue-flow__nodesselection-rect) {
  background: rgb(var(--blue-9) / 0.06);
  border: 1px dashed rgb(var(--blue-9));
  border-radius: 8px;
}

/* Controles: mismos tokens del tema, sin la caja gris de la librería. */
.jf-canvas :deep(.vue-flow__controls) {
  box-shadow: none;
  border: 1px solid rgb(var(--border-weak));
  border-radius: 12px;
  overflow: hidden;
}
.jf-canvas :deep(.vue-flow__controls-button) {
  background: rgb(var(--solid-1));
  border-bottom: 1px solid rgb(var(--border-weak));
  fill: rgb(var(--slate-11));
}
.jf-canvas :deep(.vue-flow__controls-button:hover) {
  background: rgba(var(--alpha-2));
}
</style>
