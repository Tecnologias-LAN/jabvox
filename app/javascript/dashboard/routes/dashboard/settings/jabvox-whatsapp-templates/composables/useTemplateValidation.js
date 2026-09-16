import { computed } from 'vue';

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
};

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

export function useTemplateValidation(formRef) {
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
  const counters = computed(() => ({
    header: {
      value: (formRef.value.header_content || '').length,
      max: LIMITS.HEADER_TEXT,
    },
    body: { value: (formRef.value.body || '').length, max: LIMITS.BODY },
    footer: {
      value: (formRef.value.footer || '').length,
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
    const buttons = (formRef.value.buttons || []).filter(b => b.text);
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

    buttons.forEach((b, i) => {
      if ((b.text || '').length > LIMITS.BUTTON_TEXT) {
        errs.push(
          `Botón ${i + 1}: el texto no puede superar ${LIMITS.BUTTON_TEXT} caracteres.`
        );
      }
      if (b.type === 'URL' && (b.url || '').length > LIMITS.BUTTON_URL) {
        errs.push(
          `Botón ${i + 1}: la URL no puede superar ${LIMITS.BUTTON_URL} caracteres.`
        );
      }
      if (
        (b.type === 'PHONE_NUMBER' || b.type === 'VOICE_CALL') &&
        (b.phone_number || '').length > LIMITS.BUTTON_PHONE
      ) {
        errs.push(
          `Botón ${i + 1}: el número no puede superar ${LIMITS.BUTTON_PHONE} caracteres.`
        );
      }
      if (
        b.type === 'COPY_CODE' &&
        (b.text || '').length > LIMITS.BUTTON_COPY_CODE
      ) {
        errs.push(
          `Botón ${i + 1}: el código no puede superar ${LIMITS.BUTTON_COPY_CODE} caracteres.`
        );
      }
    });

    return errs;
  });

  // ─── Errores generales (todo junto, para el gate de "Enviar a Meta") ────
  const errors = computed(() => {
    const errs = [];
    const form = formRef.value;

    if ((form.body || '').length > LIMITS.BODY) {
      errs.push(
        `El cuerpo no puede superar ${LIMITS.BODY} caracteres (tiene ${form.body.length}).`
      );
    }
    if ((form.footer || '').length > LIMITS.FOOTER) {
      errs.push(
        `El pie de página no puede superar ${LIMITS.FOOTER} caracteres.`
      );
    }
    if (
      form.header_type === 'TEXT' &&
      (form.header_content || '').length > LIMITS.HEADER_TEXT
    ) {
      errs.push(
        `El texto del encabezado no puede superar ${LIMITS.HEADER_TEXT} caracteres.`
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
