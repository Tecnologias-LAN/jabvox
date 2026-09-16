// Validación por widget del formulario, campo a campo, con las reglas que Meta
// aplica al publicar el Flow. Existe para que el editor avise mientras se
// escribe en vez de fallar al publicar con un error del que no se entiende de
// dónde salió ("Property 'init-value' is not allowed in 'TextInput'").
//
// Es la única fuente de reglas: la consumen ComponentPropsEditor.vue (marca el
// campo en rojo) e InlineFlowBuilder.vue (marca el widget y bloquea el envío).
// Su equivalente del backend es Jabvox::WhatsappFlows::Validator, que vuelve a
// validar antes de publicar porque el frontend nunca es la última palabra.

import {
  getComponentMeta,
  MAX_COMPONENTS_PER_SCREEN,
} from './componentCatalog';

// Meta exige que el nombre del campo sea un identificador: lo usa como clave de
// la respuesta y en las referencias ${form.campo}.
const FIELD_NAME_RE = /^[a-zA-Z_][a-zA-Z0-9_]*$/;

// Longitud máxima de cada texto, según la referencia de componentes de Meta
// (developers.facebook.com/docs/whatsapp/flows/reference/components).
const MAX_LENGTHS = {
  TextHeading: { text: 80 },
  TextSubheading: { text: 80 },
  TextBody: { text: 4096 },
  TextCaption: { text: 409 },
  TextInput: { label: 20, helper_text: 80 },
  TextArea: { label: 20, helper_text: 80 },
  RadioButtonsGroup: { label: 30 },
  CheckboxGroup: { label: 30 },
  Dropdown: { label: 20 },
  ChipsSelector: { label: 80 },
  DatePicker: { label: 40, helper_text: 80 },
  OptIn: { label: 120 },
  EmbeddedLink: { text: 25 },
  Footer: { label: 35 },
};

// Longitud máxima del texto de cada opción de una lista.
const MAX_OPTION_TITLE = 30;

const isEmpty = (value, kind) => {
  if (kind === 'boolean') return false;
  if (kind === 'options') return !Array.isArray(value) || value.length === 0;
  if (kind === 'action') return !value || !value.name;
  return value === undefined || value === null || value === '';
};

const isValidUrl = url => {
  if (!url) return false;
  try {
    return new URL(url).protocol === 'https:';
  } catch {
    return false;
  }
};

const validateName = (value, context) => {
  if (!FIELD_NAME_RE.test(value)) {
    return [
      {
        field: 'name',
        message:
          'Solo letras, números y guion bajo, empezando por una letra (ej: nombre_cliente)',
      },
    ];
  }
  // Dos campos con el mismo nombre se pisan en la respuesta: solo llegaría uno.
  if ((context.usedNames || []).filter(n => n === value).length > 1) {
    return [
      {
        field: 'name',
        message: `Ya hay otro campo llamado "${value}" en el formulario`,
      },
    ];
  }
  return [];
};

const validateOptions = (options, field) => {
  const errors = [];
  const max = field.max || 200;
  const min = field.min || 1;

  if (options.length > max) {
    errors.push({
      field: field.key,
      message: `Máximo ${max} opciones (tiene ${options.length})`,
    });
  }
  if (options.length < min) {
    errors.push({ field: field.key, message: `Agrega al menos ${min} opción` });
  }

  const ids = options.map(o => o.id);
  options.forEach((option, index) => {
    const posicion = `Opción ${index + 1}`;
    if (!option.id) {
      errors.push({
        field: field.key,
        message: `${posicion}: falta el identificador`,
      });
    } else if (ids.filter(id => id === option.id).length > 1) {
      errors.push({
        field: field.key,
        message: `${posicion}: el identificador "${option.id}" está repetido`,
      });
    }
    if (!option.title) {
      errors.push({ field: field.key, message: `${posicion}: falta el texto` });
    } else if (option.title.length > MAX_OPTION_TITLE) {
      errors.push({
        field: field.key,
        message: `${posicion}: máximo ${MAX_OPTION_TITLE} caracteres`,
      });
    }
  });

  return errors;
};

const validateAction = (action, context) => {
  if (action.name === 'navigate') {
    if (!action.next) {
      return [
        { field: 'action', message: 'Elige a qué pantalla lleva el botón' },
      ];
    }
    if (action.next === context.screenId) {
      return [
        { field: 'action', message: 'La pantalla no puede llevar a sí misma' },
      ];
    }
  }
  if (action.name === 'open_url' && !isValidUrl(action.url)) {
    return [
      {
        field: 'action',
        message: 'Escribe una URL válida que empiece por https://',
      },
    ];
  }
  return [];
};

const countByType = components =>
  components.reduce(
    (out, c) => ({ ...out, [c.type]: (out[c.type] || 0) + 1 }),
    {}
  );

export const validateWidget = (component, context = {}) => {
  const meta = getComponentMeta(component.type);
  if (!meta) {
    return [
      { field: 'type', message: `Widget no soportado: ${component.type}` },
    ];
  }

  const props = component.props || {};
  const errors = [];

  meta.fields.forEach(field => {
    const value = props[field.key];

    if (field.required && isEmpty(value, field.kind)) {
      errors.push({
        field: field.key,
        message: `${field.label} es obligatorio`,
      });
      return;
    }
    if (isEmpty(value, field.kind)) return;

    const limit = MAX_LENGTHS[component.type]?.[field.key];
    if (limit && typeof value === 'string' && value.length > limit) {
      errors.push({
        field: field.key,
        message: `Máximo ${limit} caracteres (tiene ${value.length})`,
      });
    }

    if (field.key === 'name') errors.push(...validateName(value, context));
    if (field.kind === 'options') errors.push(...validateOptions(value, field));
    if (field.kind === 'action') errors.push(...validateAction(value, context));
  });

  return errors;
};

/**
 * Valida una pantalla completa: sus widgets y las reglas que dependen del
 * conjunto (límites por tipo, un solo botón, pantalla final con "complete").
 * Devuelve { componentId: [errores] } más los errores de la pantalla en sí
 * bajo la clave `screen`.
 */
export const validateScreen = (
  screen,
  { isLast = false, screens = [] } = {}
) => {
  const components = screen.components || [];
  const byComponent = {};
  const screenErrors = [];

  const usedNames = components.map(c => c.props?.name).filter(Boolean);

  components.forEach(component => {
    const errors = validateWidget(component, {
      usedNames,
      screenId: screen.id,
      screens,
    });
    if (errors.length) byComponent[component.id] = errors;
  });

  if (components.length > MAX_COMPONENTS_PER_SCREEN) {
    screenErrors.push(
      `Máximo ${MAX_COMPONENTS_PER_SCREEN} elementos por pantalla (tiene ${components.length})`
    );
  }

  Object.entries(countByType(components)).forEach(([type, count]) => {
    const limit = getComponentMeta(type)?.limitPerScreen;
    if (limit && count > limit) {
      const label = getComponentMeta(type).label;
      screenErrors.push(`Solo se permite(n) ${limit} "${label}" por pantalla`);
    }
  });

  if (!screen.title) screenErrors.push('La pantalla necesita un nombre');

  // Sin un campo que responder, el formulario llega vacío al negocio.
  if (isLast && !components.some(c => getComponentMeta(c.type)?.hasName)) {
    screenErrors.push(
      'Agrega al menos una pregunta para que el contacto pueda responder'
    );
  }

  if (!components.some(c => c.type === 'Footer')) {
    screenErrors.push('La pantalla necesita un botón al final');
  }

  if (screenErrors.length) byComponent.screen = screenErrors;
  return byComponent;
};

/**
 * Valida el formulario entero. Devuelve { valid, byScreen, messages } donde
 * `messages` es la lista plana para mostrar arriba y `byScreen` sirve para
 * marcar en rojo la pantalla y el widget concretos.
 */
export const validateFlow = (screens = []) => {
  const byScreen = {};
  const messages = [];

  if (!screens.length) {
    return {
      valid: false,
      byScreen,
      messages: ['Agrega al menos una pantalla'],
    };
  }

  screens.forEach((screen, index) => {
    const result = validateScreen(screen, {
      isLast: index === screens.length - 1,
      screens,
    });
    if (!Object.keys(result).length) return;

    byScreen[screen.id] = result;
    const donde = screen.title || `Pantalla ${index + 1}`;
    Object.values(result).forEach(errors => {
      errors.forEach(error => {
        messages.push(
          `${donde}: ${typeof error === 'string' ? error : error.message}`
        );
      });
    });
  });

  return { valid: messages.length === 0, byScreen, messages };
};
