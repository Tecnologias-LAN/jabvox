/**
 * NOTAS ADHESIVAS del lienzo: solo texto, solo visuales. Van DETRÁS de los
 * pasos y el motor las ignora; viajan con el grafo en la clave `notes`.
 */

function numberOr(value, fallback) {
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : fallback;
}

/** Paleta fija: las clases se escriben literales para que Tailwind las genere. */
export const NOTE_COLORS = ['amber', 'sky', 'teal', 'violet', 'slate'];

const STYLES = {
  amber: {
    box: 'border-n-amber-8 bg-n-amber-3',
    text: 'text-n-amber-12',
    placeholder: 'text-n-amber-11/60',
    handle: 'bg-n-amber-8',
    swatch: 'bg-n-amber-9',
  },
  sky: {
    box: 'border-n-blue-8 bg-n-blue-3',
    text: 'text-n-blue-12',
    placeholder: 'text-n-blue-11/60',
    handle: 'bg-n-blue-8',
    swatch: 'bg-n-blue-9',
  },
  teal: {
    box: 'border-n-teal-8 bg-n-teal-3',
    text: 'text-n-teal-12',
    placeholder: 'text-n-teal-11/60',
    handle: 'bg-n-teal-8',
    swatch: 'bg-n-teal-9',
  },
  violet: {
    box: 'border-n-iris-8 bg-n-iris-3',
    text: 'text-n-iris-12',
    placeholder: 'text-n-iris-11/60',
    handle: 'bg-n-iris-8',
    swatch: 'bg-n-iris-9',
  },
  slate: {
    box: 'border-n-weak bg-n-slate-3',
    text: 'text-n-slate-12',
    placeholder: 'text-n-slate-11/60',
    handle: 'bg-n-slate-8',
    swatch: 'bg-n-slate-9',
  },
};

/** Clases de un color de nota; cae a `amber` si el color no se reconoce. */
export function noteColorStyle(color) {
  return STYLES[color] || STYLES.amber;
}

export const NOTE_DEFAULTS = { width: 280, height: 170, color: 'amber' };

/**
 * Normaliza una nota venida del backend: rellena lo que falte y descarta lo que
 * no sea del tipo esperado, para que un grafo antiguo o manipulado no rompa el
 * lienzo.
 */
export function normalizeNote(raw, index = 0) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const pos =
    source.position && typeof source.position === 'object'
      ? source.position
      : {};
  return {
    id:
      typeof source.id === 'string' && source.id
        ? source.id
        : `note${index + 1}`,
    position: { x: numberOr(pos.x, 40), y: numberOr(pos.y, 40) },
    width: Math.max(160, numberOr(source.width, NOTE_DEFAULTS.width)),
    height: Math.max(90, numberOr(source.height, NOTE_DEFAULTS.height)),
    color: NOTE_COLORS.includes(source.color)
      ? source.color
      : NOTE_DEFAULTS.color,
    text: typeof source.text === 'string' ? source.text : '',
  };
}

/** Forma que se persiste: SIN estado de interfaz, solo geometría y contenido. */
export function serializeNote(note) {
  return {
    id: note.id,
    position: {
      x: Math.round(note.position.x),
      y: Math.round(note.position.y),
    },
    width: Math.round(note.width),
    height: Math.round(note.height),
    color: note.color,
    text: note.text || '',
  };
}

/**
 * Desplaza en cascada mientras la posición esté ocupada: dos notas creadas
 * seguidas caían en el MISMO pixel y arrastrar la de arriba parecía mover dos.
 */
export function freeNotePosition(at, existing) {
  const STEP = 28;
  const taken = (existing || []).map(n => n.position || {});
  const occupied = (x, y) =>
    taken.some(p => Math.abs(p.x - x) < 8 && Math.abs(p.y - y) < 8);
  let x = at.x;
  let y = at.y;
  for (let guard = 0; guard < 40 && occupied(x, y); guard += 1) {
    x += STEP;
    y += STEP;
  }
  return { x: Math.round(x), y: Math.round(y) };
}

/** Id libre de la serie note1, note2… evitando los ya tomados. */
export function nextNoteId(taken) {
  let index = 1;
  while (taken.has(`note${index}`)) index += 1;
  return `note${index}`;
}
