import { computed, inject, provide, ref } from 'vue';

// ARRASTRE de campos del panel de entrada a los parámetros. El estado vive en la
// vista de detalle y se comparte por provide/inject: entrada y configuración son
// hermanos y así el arrastre puede resaltar los params compatibles.

// Tipos MIME propios: llevan las dos semánticas para que decida quien recibe.
export const MIME_PATH = 'application/jabvox-field-path';
export const MIME_REF = 'application/jabvox-field-ref';

const FIELD_DRAG = Symbol('jabvox-field-drag');

// Prefijos válidos del motor. `$json` de n8n NO existe aquí.
export const VALID_PREFIXES = [
  'trigger',
  'vars',
  'node',
  'outputs',
  'item',
  'global',
  'bucle',
];

// Construye la expresión que resuelve al VALOR de un campo. `path` es siempre
// relativa al elemento, tal como la da el contrato.
export function buildValueRef(origin, path) {
  // Una ruta escapada empieza por corchete: pegarle un punto delante daría
  // `output.["contact.name"]`, que no resuelve.
  let suffix = '';
  if (path) suffix = path.startsWith('[') ? path : `.${path}`;
  if (origin.kind === 'trigger') return `{{trigger${suffix}}}`;
  if (origin.kind === 'item') return `{{item${suffix}}}`;
  return `{{node.${origin.nodeId}.output${suffix}}}`;
}

// Referencia a la COLECCIÓN completa: `{{node.<id>.items}}`. No es lo mismo que
// un campo del elemento: confundirlas hace que el bucle reciba texto, no lista.
export function buildItemsRef(origin) {
  if (origin.kind === 'trigger') return '{{trigger}}';
  if (origin.kind === 'item') return '{{item}}';
  return `{{node.${origin.nodeId}.items}}`;
}

// `{{node.<id>.items}}` solo resuelve a lista cuando el tipo DECLARA itemsPath
// (8 de los 62 del catálogo) Y esa ruta resolvió de verdad a un array. Declararlo
// no basta: con un payload que no lo cumple el asa daría una referencia rota.
export function hasItemsRef(origin, shape) {
  if (origin.kind !== 'node') return false;
  if (typeof shape?.itemsPath !== 'string' || shape.itemsPath === '') {
    return false;
  }
  // Un contrato que no dice nada del resolvado (el del catálogo) se acepta:
  // el ejemplo del tipo sí trae la colección.
  return shape.itemsPathResolved !== false;
}

// Tipos de param que pueden RECIBIR un campo soltado.
const DROPPABLE_TYPES = [
  'string',
  'text',
  'textarea',
  'code',
  'number',
  'json',
  'select',
  'key-value',
  // Una fecha que calcula un paso previo es un caso real; al soltar la
  // expresión el campo pasa a texto.
  'date',
  'time',
];

// Un select de valores cerrados (una bandeja, una prioridad) no acepta una
// ruta: solo los `dropSemantics: 'path'`, que piden el NOMBRE de un campo.
export function isDroppableParam(spec) {
  if (!spec) return false;
  if (spec.dropSemantics === 'path') return true;
  if (spec.optionsSource) return false;
  return DROPPABLE_TYPES.includes(spec.type);
}

// Qué texto recibe un param al soltar: la ruta PELADA si su `dropSemantics` es
// 'path', la expresión en cualquier otro caso.
export function textForParam(spec, field) {
  return spec?.dropSemantics === 'path' ? field.path : field.reference;
}

// Lee del dataTransfer lo que se suelta, o null si no es un campo del editor.
export function readDroppedField(event) {
  const dt = event.dataTransfer;
  if (!dt) return null;
  const path = dt.getData(MIME_PATH);
  const reference = dt.getData(MIME_REF);
  if (!path && !reference) return null;
  return { path, reference: reference || path };
}

// Escribe las dos semánticas en el dataTransfer y avisa al estado compartido.
export function writeDraggedField(event, api, field) {
  if (!event.dataTransfer) return;
  event.dataTransfer.setData(MIME_PATH, field.path);
  event.dataTransfer.setData(MIME_REF, field.reference);
  event.dataTransfer.setData('text/plain', field.reference);
  event.dataTransfer.effectAllowed = 'copy';
  api?.startDrag(field);
}

// La vista de detalle registra el estado del arrastre para sus paneles.
export function provideFieldDrag() {
  const dragged = ref(null);
  const pendingInsert = ref(null);

  const api = {
    dragged,
    dragging: computed(() => dragged.value !== null),
    pendingInsert,
    startDrag(field) {
      dragged.value = field;
    },
    endDrag() {
      dragged.value = null;
    },
    requestInsert(field) {
      pendingInsert.value = field;
    },
    clearInsert() {
      pendingInsert.value = null;
    },
  };

  provide(FIELD_DRAG, api);
  return api;
}

// Devuelve null fuera de la vista de detalle (el panel lateral de siempre), donde
// no hay de dónde arrastrar y el resaltado no aplica.
export function useFieldDrag() {
  return inject(FIELD_DRAG, null);
}
