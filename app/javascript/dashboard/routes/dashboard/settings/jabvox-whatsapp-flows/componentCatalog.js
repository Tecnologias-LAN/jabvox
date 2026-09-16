// Catálogo de componentes de WhatsApp Flows (Flow JSON 7.3) — sección 2.3/4.3
// de docs/whatsapp-flows/architecture.md. El builder SOLO ofrece estos 15
// tipos; no se agregan otros aunque Meta los soporte (PhotoPicker,
// CalendarPicker, NavigationList, etc. quedan fuera de alcance v1).
//
// Cada entrada describe metadata suficiente para que ComponentPropsEditor.vue
// renderice el formulario de props sin un editor a mano por tipo, y para que
// ScreenEditor.vue valide límites por pantalla antes de publicar.
//
// `fields`: lista de campos de props que el editor genérico debe mostrar.
//   - kind: 'text' | 'textarea' | 'boolean' | 'select' | 'options' | 'action' | 'number'
//   - required: si el campo es obligatorio para que el componente sea válido
//   - variableAllowed: si el campo acepta `${screen...}`/`${data...}` vía VariablePicker

const TEXT_FIELDS = [
  { key: 'text', label: 'Texto', kind: 'textarea', required: true },
];

const INPUT_NAME_FIELD = {
  key: 'name',
  label: 'Nombre del campo',
  kind: 'text',
  required: true,
  hint: 'Clave interna usada en la respuesta (response_json) y en variables.',
};

const LABEL_FIELD = {
  key: 'label',
  label: 'Etiqueta',
  kind: 'text',
  required: true,
  variableAllowed: true,
};

const REQUIRED_FIELD = {
  key: 'required',
  label: 'Obligatorio',
  kind: 'boolean',
  default: false,
};

export const COMPONENT_CATALOG = {
  TextHeading: {
    label: 'Título',
    icon: 'i-lucide-heading-1',
    category: 'text',
    maxLength: 80,
    fields: [{ ...TEXT_FIELDS[0], maxLength: 80, variableAllowed: true }],
  },
  TextSubheading: {
    label: 'Subtítulo',
    icon: 'i-lucide-heading-2',
    category: 'text',
    maxLength: 80,
    fields: [{ ...TEXT_FIELDS[0], maxLength: 80, variableAllowed: true }],
  },
  TextBody: {
    label: 'Párrafo',
    icon: 'i-lucide-text',
    category: 'text',
    maxLength: 4096,
    fields: [{ ...TEXT_FIELDS[0], maxLength: 4096, variableAllowed: true }],
  },
  TextCaption: {
    label: 'Texto pequeño',
    icon: 'i-lucide-type',
    category: 'text',
    maxLength: 409,
    fields: [{ ...TEXT_FIELDS[0], maxLength: 409, variableAllowed: true }],
  },
  TextInput: {
    label: 'Campo de texto',
    icon: 'i-lucide-text-cursor-input',
    category: 'input',
    hasName: true,
    fields: [
      INPUT_NAME_FIELD,
      LABEL_FIELD,
      {
        key: 'input_type',
        label: 'Tipo de entrada',
        kind: 'select',
        options: ['text', 'number', 'email', 'password', 'phone'],
        default: 'text',
      },
      REQUIRED_FIELD,
    ],
  },
  TextArea: {
    label: 'Área de texto',
    icon: 'i-lucide-align-left',
    category: 'input',
    hasName: true,
    maxLength: 600,
    fields: [INPUT_NAME_FIELD, LABEL_FIELD, REQUIRED_FIELD],
  },
  RadioButtonsGroup: {
    label: 'Selección única (radio)',
    icon: 'i-lucide-circle-dot',
    category: 'choice',
    hasName: true,
    minOptions: 1,
    maxOptions: 20,
    fields: [
      INPUT_NAME_FIELD,
      LABEL_FIELD,
      {
        key: 'data_source',
        label: 'Opciones',
        kind: 'options',
        required: true,
        min: 1,
        max: 20,
      },
      REQUIRED_FIELD,
    ],
  },
  CheckboxGroup: {
    label: 'Selección múltiple (checkbox)',
    icon: 'i-lucide-list-checks',
    category: 'choice',
    hasName: true,
    minOptions: 1,
    maxOptions: 20,
    fields: [
      INPUT_NAME_FIELD,
      LABEL_FIELD,
      {
        key: 'data_source',
        label: 'Opciones',
        kind: 'options',
        required: true,
        min: 1,
        max: 20,
      },
      REQUIRED_FIELD,
    ],
  },
  Dropdown: {
    label: 'Lista desplegable',
    icon: 'i-lucide-chevron-down-square',
    category: 'choice',
    hasName: true,
    minOptions: 1,
    maxOptions: 200,
    fields: [
      INPUT_NAME_FIELD,
      LABEL_FIELD,
      {
        key: 'data_source',
        label: 'Opciones',
        kind: 'options',
        required: true,
        min: 1,
        max: 200,
      },
      REQUIRED_FIELD,
    ],
  },
  ChipsSelector: {
    label: 'Selector de chips',
    icon: 'i-lucide-tags',
    category: 'choice',
    hasName: true,
    minOptions: 1,
    maxOptions: 20,
    fields: [
      INPUT_NAME_FIELD,
      LABEL_FIELD,
      {
        key: 'data_source',
        label: 'Opciones',
        kind: 'options',
        required: true,
        min: 1,
        max: 20,
      },
      REQUIRED_FIELD,
    ],
  },
  DatePicker: {
    label: 'Selector de fecha',
    icon: 'i-lucide-calendar',
    category: 'input',
    hasName: true,
    fields: [INPUT_NAME_FIELD, LABEL_FIELD, REQUIRED_FIELD],
  },
  OptIn: {
    label: 'Casilla de consentimiento',
    icon: 'i-lucide-shield-check',
    category: 'choice',
    hasName: true,
    limitPerScreen: 5,
    fields: [INPUT_NAME_FIELD, LABEL_FIELD, REQUIRED_FIELD],
  },
  Image: {
    label: 'Imagen',
    icon: 'i-lucide-image',
    category: 'media',
    limitPerScreen: 3,
    fields: [
      {
        key: 'src',
        label: 'Imagen (base64)',
        kind: 'image',
        required: true,
        hint: 'Se convierte a base64 al subir el archivo.',
      },
      {
        key: 'alt_text',
        label: 'Texto alternativo',
        kind: 'text',
        optional: true,
      },
    ],
  },
  EmbeddedLink: {
    label: 'Enlace embebido',
    icon: 'i-lucide-link',
    category: 'action',
    limitPerScreen: 2,
    fields: [
      { key: 'text', label: 'Texto del enlace', kind: 'text', required: true },
      { key: 'action', label: 'Acción', kind: 'action', required: true },
    ],
  },
  Footer: {
    label: 'Pie de pantalla (botón)',
    icon: 'i-lucide-square-mouse-pointer',
    category: 'action',
    limitPerScreen: 1,
    fields: [
      { key: 'label', label: 'Texto del botón', kind: 'text', required: true },
      { key: 'action', label: 'Acción', kind: 'action', required: true },
    ],
  },
};

export const COMPONENT_TYPES = Object.keys(COMPONENT_CATALOG);

export const COMPONENT_CATEGORIES = [
  { key: 'text', label: 'Texto' },
  { key: 'input', label: 'Campos' },
  { key: 'choice', label: 'Selección' },
  { key: 'media', label: 'Media' },
  { key: 'action', label: 'Acción' },
];

// Límites globales por pantalla (sección 2.3): máx 50 componentes, y los
// límites específicos por tipo (Footer=1, Image=3, EmbeddedLink=2, OptIn=5)
// viven en `limitPerScreen` de cada entrada de arriba.
export const MAX_COMPONENTS_PER_SCREEN = 50;

/** Devuelve la metadata de un tipo de componente, o null si no existe en el catálogo. */
export const getComponentMeta = type => COMPONENT_CATALOG[type] || null;

/** Crea un componente nuevo con props por defecto según su metadata. */
export const createComponentInstance = (type, id) => {
  const meta = getComponentMeta(type);
  if (!meta) return null;
  const props = {};
  meta.fields.forEach(field => {
    if (field.kind === 'boolean') {
      props[field.key] = field.default ?? false;
    } else if (field.kind === 'options') {
      props[field.key] = [];
    } else if (field.kind === 'action') {
      props[field.key] = { name: 'navigate', next: '' };
    } else if (field.default !== undefined) {
      props[field.key] = field.default;
    } else {
      props[field.key] = '';
    }
  });
  return { id, type, props };
};

/**
 * Cuenta cuántas instancias de un tipo con `limitPerScreen` ya hay en una
 * pantalla, para bloquear agregar más desde la paleta.
 */
export const countByType = (components, type) =>
  (components || []).filter(c => c.type === type).length;

export const isAtLimit = (components, type) => {
  const meta = getComponentMeta(type);
  if (!meta?.limitPerScreen) return false;
  return countByType(components, type) >= meta.limitPerScreen;
};
