/**
 * AUTOGUARDADO del editor de flujos.
 *
 * El backend versiona en CADA `PUT /versions`, así que guardar con el debounce
 * de 1,5 s que usa n8n llenaría el historial de basura. Aquí el debounce solo
 * decide CUÁNDO hay que mirar; una VENTANA MÍNIMA entre envíos limita el
 * historial a una versión por minuto de edición continua.
 */

// Debounce: espera a que el usuario pare de tocar el lienzo.
export const AUTOSAVE_DEBOUNCE_MS = 2000;
// Tope del debounce: editando sin pausa, se guarda igualmente cada 10 s.
export const AUTOSAVE_MAX_WAIT_MS = 10000;
// Ventana mínima entre versiones creadas por el autoguardado.
export const AUTOSAVE_MIN_INTERVAL_MS = 60000;

// Serializa con las claves ORDENADAS: dos params iguales escritos en distinto
// orden tienen que dar la misma huella.
function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === 'object') {
    return Object.keys(value)
      .sort()
      .reduce((acc, key) => {
        acc[key] = stableValue(value[key]);
        return acc;
      }, {});
  }
  return value;
}

/**
 * Huella del grafo para comparar POR CONTENIDO. Vue Flow muta los objetos en
 * sitio, así que comparar referencias dispararía en cada render.
 *
 * Se ordena por id y se redondean las posiciones: arrastrar un paso un pixel al
 * hacer clic no es un cambio que merezca una versión.
 */
export function graphFingerprint(graph) {
  if (!graph) return '';
  const nodes = [...(graph.nodes || [])]
    .map(n => ({
      id: n.id,
      type: n.type,
      x: Math.round((n.position?.x ?? 0) / 8),
      y: Math.round((n.position?.y ?? 0) / 8),
      label: n.data?.label ?? '',
      params: stableValue(n.params ?? n.data?.params ?? {}),
    }))
    .sort((a, b) => String(a.id).localeCompare(String(b.id)));
  const edges = [...(graph.edges || [])]
    .map(e => `${e.source}>${e.sourceHandle ?? ''}>${e.target}`)
    .sort();
  const notes = [...(graph.notes || [])]
    .map(n => ({
      id: n.id,
      x: Math.round((n.position?.x ?? 0) / 8),
      y: Math.round((n.position?.y ?? 0) / 8),
      w: Math.round((n.width ?? 0) / 8),
      h: Math.round((n.height ?? 0) / 8),
      color: n.color,
      text: n.text ?? '',
    }))
    .sort((a, b) => String(a.id).localeCompare(String(b.id)));
  return JSON.stringify({ nodes, edges, notes });
}

/**
 * Planificador del autoguardado. Es lógica PURA: no toca Vue ni el reloj del
 * sistema, recibe `now` y devuelve qué hay que hacer. Así se puede probar.
 */
export function createAutosaveScheduler({
  debounceMs = AUTOSAVE_DEBOUNCE_MS,
  maxWaitMs = AUTOSAVE_MAX_WAIT_MS,
  minIntervalMs = AUTOSAVE_MIN_INTERVAL_MS,
} = {}) {
  // Huella ya guardada en el servidor; null = todavía no se ha cargado nada.
  let savedFingerprint = null;
  // Momento del primer cambio no guardado, para respetar `maxWaitMs`.
  let dirtySince = null;
  let lastChangeAt = null;
  let lastSaveAt = null;

  return {
    /** Fija la huella de referencia tras cargar o guardar. */
    markSaved(fingerprint, now) {
      savedFingerprint = fingerprint;
      dirtySince = null;
      lastChangeAt = null;
      if (now !== undefined) lastSaveAt = now;
    },

    /** Registra un cambio. Devuelve true si de verdad difiere de lo guardado. */
    noteChange(fingerprint, now) {
      if (savedFingerprint === null) {
        savedFingerprint = fingerprint;
        return false;
      }
      if (fingerprint === savedFingerprint) {
        // Volvió al estado guardado (deshacer manual): ya no hay nada pendiente.
        dirtySince = null;
        lastChangeAt = null;
        return false;
      }
      if (dirtySince === null) dirtySince = now;
      lastChangeAt = now;
      return true;
    },

    isDirty() {
      return dirtySince !== null;
    },

    /**
     * ¿Toca guardar ahora? Exige las tres condiciones: hay cambios, el usuario
     * paró (o se agotó `maxWaitMs`), y la ventana mínima ya pasó.
     */
    shouldSave(now) {
      if (dirtySince === null) return false;
      const settled = now - lastChangeAt >= debounceMs;
      const forced = now - dirtySince >= maxWaitMs;
      if (!settled && !forced) return false;
      if (lastSaveAt !== null && now - lastSaveAt < minIntervalMs) return false;
      return true;
    },

    /** Milisegundos hasta el próximo instante en que podría tocar guardar. */
    nextCheckDelay(now) {
      if (dirtySince === null) return null;
      const untilSettled = Math.max(0, lastChangeAt + debounceMs - now);
      const untilForced = Math.max(0, dirtySince + maxWaitMs - now);
      const untilWindow =
        lastSaveAt === null ? 0 : Math.max(0, lastSaveAt + minIntervalMs - now);
      return Math.max(Math.min(untilSettled, untilForced), untilWindow);
    },

    /** Estado interno, para las pruebas. */
    snapshot() {
      return { savedFingerprint, dirtySince, lastChangeAt, lastSaveAt };
    },
  };
}
