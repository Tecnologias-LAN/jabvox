import { computed } from 'vue';

import { textLength } from '../helpers/whatsappFormatting';

/**
 * Validación en vivo del wizard de plantillas de WhatsApp, con paridad con el
 * editor de Meta Business Manager: avisa ANTES de intentar guardar/publicar,
 * no solo mostrando el error crudo de Meta después del hecho (sección 4 de
 * docs/whatsapp-flows/templates-full-coverage.md). Replica en el cliente las
 * mismas reglas que Jabvox::WhatsappTemplatesManager aplica en el servidor
 * (fuente autoritativa) — el frontend nunca reemplaza esa validación, solo
 * adelanta el feedback.
 *
 * Recibe un `formRef` reactivo (ref/reactive) con la forma del wizard y
 * expone `{ errors, isValid, limits, counters, ... }` consumidos por
 * WhatsappTemplatesSettings.vue.
 */

export const LIMITS = {
  HEADER_TEXT: 60,
  BODY: 1024,
  FOOTER: 60,
  BUTTON_TEXT: 25,
  BUTTON_URL: 2000,
  BUTTON_PHONE: 20,
  BUTTON_COPY_CODE: 20,
  NAME: 512,
};

// Meta exige que el nombre sea solo minúsculas, números y guion bajo (máx 512).
// Mayúsculas, espacios, acentos o guiones medios hacen que rechace la plantilla
// al crearla. Se valida en el editor para no descubrirlo tras el envío.
export function isValidTemplateName(name) {
  const value = (name || '').trim();
  if (!value) return false;
  if (value.length > LIMITS.NAME) return false;
  return /^[a-z0-9_]+$/.test(value);
}

// Convierte lo que escribe la persona a un nombre válido de Meta: a minúsculas,
// espacios y guiones a guion bajo, acentos sin tilde y fuera cualquier otro
// símbolo. Así "Mi Plantilla 2!" queda "mi_plantilla_2" mientras se escribe.
export function sanitizeTemplateName(name) {
  return (name || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // quita acentos
    .replace(/[\s-]+/g, '_') // espacios y guiones medios -> guion bajo
    .replace(/[^a-z0-9_]/g, '') // fuera todo lo demás
    .slice(0, LIMITS.NAME);
}

export const BUTTON_TYPE_MAX = {
  QUICK_REPLY: 10,
  URL: 2,
  PHONE_NUMBER: 1,
  VOICE_CALL: 1,
  COPY_CODE: 1,
  OTP: 1,
};

export const BUTTON_MAX_TOTAL = 10;

// ─── Helpers de variables (reutilizables fuera del composable también) ───────
export function detectVariables(text) {
  const matches = (text || '').match(/\{\{([^}]+)\}\}/g) || [];
  return [...new Set(matches.map(m => m.replace(/[{}]/g, '').trim()))];
}

export function hasEdgeVariable(text) {
  const body = (text || '').trim();
  if (!body) return false;
  return /^\{\{[^}]+\}\}/.test(body) || /\{\{[^}]+\}\}$/.test(body);
}

export function hasConsecutiveVariables(text) {
  const body = text || '';
  const re = /\{\{[^}]+\}\}(\s*)\{\{[^}]+\}\}/g;
  let match = re.exec(body);
  while (match) {
    if (!match[1] || !match[1].trim()) return true;
    match = re.exec(body);
  }
  return false;
}

export function hasMixedVariableTypes(vars) {
  const numeric = vars.filter(v => /^[0-9]+$/.test(v));
  const named = vars.filter(v => !/^[0-9]+$/.test(v));
  return numeric.length > 0 && named.length > 0;
}

export function hasInvalidNamedVars(vars) {
  return vars.filter(v => !/^[0-9]+$/.test(v) && !/^[a-z0-9_]+$/.test(v));
}

export function isNonSequentialPositional(vars) {
  const numeric = vars.filter(v => /^[0-9]+$/.test(v));
  if (!numeric.length) return false;
  const nums = numeric.map(n => parseInt(n, 10)).sort((a, b) => a - b);
  return !nums.every((n, i) => n === i + 1);
}

// Meta NO aplica formato (*negrita*, _cursiva_, ~tachado~) fuera del cuerpo:
// en el encabezado y el pie los marcadores salen literales al cliente.
const FORMAT_MARKERS = /(\*[^\s*][^*]*\*)|(_[^\s_][^_]*_)|(~[^\s~][^~]*~)/;

export function hasFormattingMarkers(text) {
  return FORMAT_MARKERS.test(text || '');
}

// El encabezado de texto y el pie son de una sola línea.
export function hasNewline(text) {
  return /[\r\n]/.test(text || '');
}

// Meta admite UNA variable en el encabezado y NINGUNA en el pie.
export function countVariables(text) {
  return ((text || '').match(/\{\{[^}]+\}\}/g) || []).length;
}

// En una URL la variable solo puede ir al final (sufijo dinámico).
export function urlVariableNotAtEnd(url) {
  const value = url || '';
  if (!countVariables(value)) return false;
  return !/\{\{[^}]+\}\}$/.test(value.trim());
}

// Dos botones con el mismo texto los rechaza Meta.
export function duplicateButtonTexts(buttons) {
  const vistos = new Map();
  const dups = new Set();
  buttons.forEach(b => {
    const key = (b.text || '').trim().toLowerCase();
    if (!key) return;
    if (vistos.has(key)) dups.add(b.text.trim());
    vistos.set(key, true);
  });
  return [...dups];
}

// True si los botones del mismo tipo quedan agrupados (no intercalados).
function buttonsGroupedByType(types) {
  const seenOrder = [...new Set(types)];
  const rebuilt = [];
  seenOrder.forEach(t => {
    types.forEach(x => {
      if (x === t) rebuilt.push(x);
    });
  });
  return rebuilt.join('|') === types.join('|');
}

// `isEditingRef` (opcional): al editar una plantilla el nombre ya existe en Meta
// y no se puede cambiar, así que no se valida su formato. Si no se pasa, se asume
// creación (se valida siempre).
export function useTemplateValidation(formRef, isEditingRef = null) {
  // ─── Variables del body ────────────────────────────────────────────────
  const detectedVars = computed(() => detectVariables(formRef.value.body));

  const invalidVars = computed(() => hasInvalidNamedVars(detectedVars.value));

  const bodyHasEdgeVar = computed(() => hasEdgeVariable(formRef.value.body));

  const bodyHasConsecutiveVars = computed(() =>
    hasConsecutiveVariables(formRef.value.body)
  );

  const bodyHasMixedVarTypes = computed(() =>
    hasMixedVariableTypes(detectedVars.value)
  );

  const bodyHasNonSequentialVars = computed(() =>
    isNonSequentialPositional(detectedVars.value)
  );

  // ─── Contadores de longitud ────────────────────────────────────────────
  // Se cuenta en CARACTERES reales, no en unidades UTF-16: '😊'.length es 2 y
  // '👨‍👩‍👧'.length es 8, así que con `.length` el editor bloqueaba textos con
  // emojis que sí caben dentro del límite de Meta.
  const counters = computed(() => ({
    header: {
      value: textLength(formRef.value.header_content),
      max: LIMITS.HEADER_TEXT,
    },
    body: { value: textLength(formRef.value.body), max: LIMITS.BODY },
    footer: {
      value: textLength(formRef.value.footer),
      max: LIMITS.FOOTER,
    },
  }));

  const counterClass = (value, max) => {
    if (value > max) return 'text-n-ruby-11';
    if (value >= max * 0.9) return 'text-n-amber-11';
    return 'text-n-slate-10';
  };

  // ─── Botones ────────────────────────────────────────────────────────────
  const buttonErrors = computed(() => {
    const errs = [];
    // COPY_CODE no lleva texto editable (Meta lo fija); se incluye igual para
    // contarlo en los topes y validar su código (b.example).
    const buttons = (formRef.value.buttons || []).filter(
      b => b.text || b.type === 'COPY_CODE'
    );
    if (!buttons.length) return errs;

    if (buttons.length > BUTTON_MAX_TOTAL) {
      errs.push(
        `Máximo ${BUTTON_MAX_TOTAL} botones combinados (hay ${buttons.length}).`
      );
    }

    const types = buttons.map(b => b.type);

    if (types.includes('COPY_CODE') && new Set(types).size > 1) {
      errs.push(
        'El botón COPY_CODE no puede combinarse con ningún otro tipo de botón.'
      );
    }

    if (types.includes('PHONE_NUMBER') && types.includes('VOICE_CALL')) {
      errs.push(
        'Los botones PHONE_NUMBER y VOICE_CALL son mutuamente excluyentes.'
      );
    }

    Object.entries(BUTTON_TYPE_MAX).forEach(([type, max]) => {
      const count = types.filter(t => t === type).length;
      if (count > max) {
        errs.push(`Máximo ${max} botón(es) de tipo ${type} (hay ${count}).`);
      }
    });

    if (!buttonsGroupedByType(types)) {
      errs.push(
        'Los botones del mismo tipo deben ir agrupados (no intercalados con otros tipos).'
      );
    }

    const dups = duplicateButtonTexts(buttons);
    if (dups.length) {
      errs.push(
        `Dos botones no pueden tener el mismo texto: ${dups.join(', ')}.`
      );
    }

    buttons.forEach((b, i) => {
      if (textLength(b.text) > LIMITS.BUTTON_TEXT) {
        errs.push(
          `Botón ${i + 1}: el texto no puede superar ${LIMITS.BUTTON_TEXT} caracteres.`
        );
      }
      if (b.type === 'URL' && textLength(b.url) > LIMITS.BUTTON_URL) {
        errs.push(
          `Botón ${i + 1}: la URL no puede superar ${LIMITS.BUTTON_URL} caracteres.`
        );
      }
      if (
        (b.type === 'PHONE_NUMBER' || b.type === 'VOICE_CALL') &&
        textLength(b.phone_number) > LIMITS.BUTTON_PHONE
      ) {
        errs.push(
          `Botón ${i + 1}: el número no puede superar ${LIMITS.BUTTON_PHONE} caracteres.`
        );
      }
      // El código de oferta se edita en b.example, no en b.text (el texto del
      // botón lo fija Meta). La longitud se valida sobre el campo real.
      if (
        b.type === 'COPY_CODE' &&
        textLength(b.example) > LIMITS.BUTTON_COPY_CODE
      ) {
        errs.push(
          `Botón ${i + 1}: el código no puede superar ${LIMITS.BUTTON_COPY_CODE} caracteres.`
        );
      }
      if (b.type === 'URL') {
        if (countVariables(b.url) > 1) {
          errs.push(`Botón ${i + 1}: la URL admite como máximo una variable.`);
        } else if (urlVariableNotAtEnd(b.url)) {
          errs.push(
            `Botón ${i + 1}: la variable de la URL solo puede ir al final (p. ej. https://tusitio.com/{{1}}).`
          );
        }
      }
    });

    return errs;
  });

  // ─── Errores generales (todo junto, para el gate de "Enviar a Meta") ────
  const errors = computed(() => {
    const errs = [];
    const form = formRef.value;

    // El nombre solo se valida al crear: al editar ya existe en Meta y es fijo.
    const isEditing = isEditingRef ? isEditingRef.value : false;
    if (!isEditing && form.name && !isValidTemplateName(form.name)) {
      errs.push(
        'El nombre solo admite minúsculas, números y guion bajo (sin espacios, mayúsculas ni acentos).'
      );
    }

    if (textLength(form.body) > LIMITS.BODY) {
      errs.push(
        `El cuerpo no puede superar ${LIMITS.BODY} caracteres (tiene ${textLength(form.body)}).`
      );
    }
    if (textLength(form.footer) > LIMITS.FOOTER) {
      errs.push(
        `El pie de página no puede superar ${LIMITS.FOOTER} caracteres.`
      );
    }
    if (
      form.header_type === 'TEXT' &&
      textLength(form.header_content) > LIMITS.HEADER_TEXT
    ) {
      errs.push(
        `El texto del encabezado no puede superar ${LIMITS.HEADER_TEXT} caracteres.`
      );
    }
    // Botón de Flow: su texto tiene el mismo tope que un botón normal (25). Se
    // valida aquí porque el botón de Flow vive en form.flow_button_text, fuera
    // del array de botones que recorre buttonErrors.
    if (textLength(form.flow_button_text) > LIMITS.BUTTON_TEXT) {
      errs.push(
        `El texto del botón de Flow no puede superar ${LIMITS.BUTTON_TEXT} caracteres.`
      );
    }

    if (invalidVars.value.length) {
      errs.push(
        `Nombres de variable inválidos: ${invalidVars.value
          .map(v => `{{${v}}}`)
          .join(', ')}. Usa solo minúsculas, números y guion bajo.`
      );
    }
    if (bodyHasEdgeVar.value) {
      errs.push(
        'El cuerpo no puede empezar ni terminar con una variable. Agrega texto fijo antes y después.'
      );
    }
    if (bodyHasConsecutiveVars.value) {
      errs.push(
        'Dos variables no pueden ir consecutivas sin texto entre ellas.'
      );
    }
    if (bodyHasMixedVarTypes.value) {
      errs.push(
        'No se pueden mezclar variables posicionales ({{1}}) y con nombre ({{nombre}}) en el mismo cuerpo.'
      );
    }
    if (!bodyHasMixedVarTypes.value && bodyHasNonSequentialVars.value) {
      errs.push(
        'Las variables posicionales deben ser secuenciales sin saltos: {{1}}, {{2}}, {{3}}… (no {{1}}, {{3}}).'
      );
    }

    // ── Encabezado de texto ────────────────────────────────────────────
    if (form.header_type === 'TEXT' && form.header_content) {
      if (countVariables(form.header_content) > 1) {
        errs.push('El encabezado admite como máximo una variable.');
      }
      if (hasNewline(form.header_content)) {
        errs.push('El encabezado no admite saltos de línea.');
      }
      // Meta no interpreta *negrita* fuera del cuerpo: los marcadores llegarían
      // literales al cliente.
      if (hasFormattingMarkers(form.header_content)) {
        errs.push(
          'El encabezado no admite formato (*negrita*, _cursiva_, ~tachado~): los símbolos se verían tal cual.'
        );
      }
    }

    // ── Pie de página ──────────────────────────────────────────────────
    if (form.footer) {
      if (countVariables(form.footer)) {
        errs.push('El pie de página no admite variables.');
      }
      if (hasNewline(form.footer)) {
        errs.push('El pie de página no admite saltos de línea.');
      }
      if (hasFormattingMarkers(form.footer)) {
        errs.push(
          'El pie de página no admite formato (*negrita*, _cursiva_, ~tachado~): los símbolos se verían tal cual.'
        );
      }
    }

    // ── Botones de las tarjetas del carrusel ───────────────────────────
    // Tienen el mismo tope de texto (25) que un botón normal, pero viven en
    // form.cards[].buttons, fuera del array que recorre buttonErrors.
    (form.cards || []).forEach((card, ci) => {
      (card.buttons || []).forEach((b, bi) => {
        const where = `Tarjeta ${ci + 1}, botón ${bi + 1}`;
        if (textLength(b.text) > LIMITS.BUTTON_TEXT) {
          errs.push(
            `${where}: el texto no puede superar ${LIMITS.BUTTON_TEXT} caracteres.`
          );
        }
        if (b.type === 'URL' && textLength(b.url) > LIMITS.BUTTON_URL) {
          errs.push(
            `${where}: la URL no puede superar ${LIMITS.BUTTON_URL} caracteres.`
          );
        }
        if (
          (b.type === 'PHONE_NUMBER' || b.type === 'VOICE_CALL') &&
          textLength(b.phone_number) > LIMITS.BUTTON_PHONE
        ) {
          errs.push(
            `${where}: el número no puede superar ${LIMITS.BUTTON_PHONE} caracteres.`
          );
        }
        if (b.type === 'URL' && urlVariableNotAtEnd(b.url)) {
          errs.push(
            `${where}: la variable de la URL solo puede ir al final (p. ej. https://tusitio.com/{{1}}).`
          );
        }
      });
    });

    errs.push(...buttonErrors.value);

    return errs;
  });

  const isValid = computed(() => errors.value.length === 0);

  return {
    detectedVars,
    invalidVars,
    bodyHasEdgeVar,
    bodyHasConsecutiveVars,
    bodyHasMixedVarTypes,
    bodyHasNonSequentialVars,
    counters,
    counterClass,
    buttonErrors,
    errors,
    isValid,
  };
}
