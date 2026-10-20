/**
 * Formato de texto de WhatsApp para la vista previa de plantillas.
 *
 * WhatsApp NO usa Markdown: delimita con UN solo carácter a cada lado
 * (*negrita*, _cursiva_, ~tachado~, ```monoespaciado```). Escribir `**texto**`
 * no da negrita: WhatsApp consume el par interno y deja los asteriscos sobrantes
 * a la vista.
 *
 * Reglas que replica este helper, tomadas del comportamiento real del cliente:
 *   - El delimitador no puede estar pegado a un espacio por dentro:
 *     `*hola*` da negrita, `* hola *` no.
 *   - No se formatea a través de saltos de línea: un `*` suelto en una línea no
 *     "contagia" a la siguiente.
 *   - Los formatos se anidan: `*_texto_*` sale en negrita y cursiva.
 */

// Longitud en CARACTERES reales, no en unidades UTF-16.
//
// `'😊'.length` es 2 y `'👨‍👩‍👧'.length` es 8, porque JavaScript cuenta pares
// subrogados. Con límites pequeños (25 en un botón, 60 en el encabezado) eso
// bloquea textos que sí caben. Intl.Segmenter agrupa además los emojis
// compuestos por ZWJ, que es como los cuenta una persona al mirarlos.
const segmenter =
  typeof Intl !== 'undefined' && Intl.Segmenter
    ? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
    : null;

export const textLength = text => {
  const value = text ?? '';
  if (!value) return 0;
  if (segmenter) return [...segmenter.segment(value)].length;
  // Sin Intl.Segmenter: [...str] ya respeta los pares subrogados (😊 = 1),
  // aunque cuente por separado las partes de un emoji compuesto.
  return [...value].length;
};

const ESCAPES = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

// El texto de la plantilla lo escribe el usuario y se pinta con v-html: se escapa
// SIEMPRE antes de aplicar formato, o un `<script>` escrito en el cuerpo se
// ejecutaría en el panel.
export const escapeHtml = text =>
  (text ?? '').replace(/[&<>"']/g, char => ESCAPES[char]);

// Un marcador no puede abrir ni cerrar pegado a un espacio, y no cruza saltos de
// línea. `[^\s]` en los extremos cubre ambas cosas: el contenido empieza y acaba
// en algo que no sea espacio (y \n es espacio).
const rule = (marker, tag) => ({
  re: new RegExp(
    `${marker}(?!\\s)((?:(?!${marker})[^\\n])*[^\\s${marker}]|[^\\s${marker}])${marker}`,
    'g'
  ),
  tag,
});

// El monoespaciado va primero: su delimitador (```) contiene asteriscos y, si se
// procesara después, la regla de negrita ya habría partido el bloque.
const MONOSPACE = /```([\s\S]+?)```/g;

const INLINE_RULES = [rule('\\*', 'strong'), rule('_', 'em'), rule('~', 'del')];

/**
 * Convierte el formato de WhatsApp en HTML seguro para la vista previa.
 * Devuelve siempre HTML escapado: apto para v-html.
 */
export const formatWhatsappText = text => {
  const value = text ?? '';
  if (!value) return '';

  let html = escapeHtml(value);
  html = html.replace(MONOSPACE, '<code>$1</code>');
  INLINE_RULES.forEach(({ re, tag }) => {
    html = html.replace(re, `<${tag}>$1</${tag}>`);
  });
  return html;
};

/**
 * Envuelve el trozo seleccionado de un textarea/input con un marcador, o lo
 * desenvuelve si ya lo tenía (segundo clic en el mismo botón).
 *
 * Devuelve { value, start, end } para que quien llama reponga la selección: sin
 * eso, el cursor salta al final y hay que volver a seleccionar a mano.
 */
export const toggleMarker = (text, selectionStart, selectionEnd, marker) => {
  const value = text ?? '';
  const start = Math.min(selectionStart, selectionEnd);
  const end = Math.max(selectionStart, selectionEnd);
  const selected = value.slice(start, end);

  // Sin selección no hay nada que envolver: se dejan los marcadores y el cursor
  // en medio para escribir dentro.
  if (!selected) {
    return {
      value: `${value.slice(0, start)}${marker}${marker}${value.slice(end)}`,
      start: start + marker.length,
      end: start + marker.length,
    };
  }

  const len = marker.length;
  const yaDentro =
    value.slice(Math.max(0, start - len), start) === marker &&
    value.slice(end, end + len) === marker;

  if (yaDentro) {
    return {
      value: `${value.slice(0, start - len)}${selected}${value.slice(end + len)}`,
      start: start - len,
      end: end - len,
    };
  }

  const yaEnvuelto =
    selected.length > len * 2 &&
    selected.startsWith(marker) &&
    selected.endsWith(marker);

  if (yaEnvuelto) {
    const limpio = selected.slice(len, -len);
    return {
      value: `${value.slice(0, start)}${limpio}${value.slice(end)}`,
      start,
      end: start + limpio.length,
    };
  }

  return {
    value: `${value.slice(0, start)}${marker}${selected}${marker}${value.slice(end)}`,
    start: start + len,
    end: end + len,
  };
};
