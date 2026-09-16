// Compilador LOCAL de screens_json -> Flow JSON 7.3, puro (sin I/O). Es un
// espejo del `Jabvox::WhatsappFlows::JsonCompiler` del backend (sección 5.2
// de docs/whatsapp-flows/architecture.md) usado SOLO para el preview
// inmediato del JSON en el builder (FlowJsonView.vue) — el compilado
// autoritativo que se manda a Meta sigue siendo el del backend en /publish.
//
// Reglas de mapeo (sección 4.3): props snake_case -> claves kebab-case de
// Meta (data_source -> data-source, input_type -> input-type, etc.).

const FLOW_JSON_VERSION = '7.3';

const PROP_KEY_MAP = {
  data_source: 'data-source',
  input_type: 'input-type',
  init_value: 'init-value',
  alt_text: 'alt-text',
};

const mapPropKey = key => PROP_KEY_MAP[key] || key;

// Nombre del Form que envuelve los componentes. Meta solo resuelve
// ${form.campo} dentro de un Form; el nombre en sí es libre.
const FORM_NAME = 'flow_path';

// Componentes que capturan una respuesta y por tanto viajan en el payload.
const INPUT_TYPES = new Set([
  'TextInput',
  'TextArea',
  'RadioButtonsGroup',
  'CheckboxGroup',
  'Dropdown',
  'ChipsSelector',
  'DatePicker',
  'OptIn',
]);

const PAYLOAD_ACTIONS = new Set(['complete', 'navigate', 'data_exchange']);

const fieldNames = screen =>
  (screen.components || [])
    .filter(c => INPUT_TYPES.has(c.type))
    .map(c => c.props?.name)
    .filter(Boolean);

// Los campos de esta pantalla se leen del formulario; los de pantallas
// anteriores, del `data` que la pantalla recibió.
const actionPayload = (fields, inherited) => {
  const payload = {};
  fields.forEach(f => {
    payload[f] = `\${form.${f}}`;
  });
  inherited.forEach(f => {
    payload[f] = `\${data.${f}}`;
  });
  return payload;
};

// El `payload` es lo que hace que Meta devuelva las respuestas en el complete
// (o las propague a la pantalla siguiente en el navigate). Sin él, la respuesta
// del formulario llega vacía, con solo el flow_token.
const compileAction = (action, fields = [], inherited = []) => {
  if (!action || !action.name) return undefined;
  const out = { name: action.name };
  if (action.name === 'navigate' && action.next)
    out.next = { type: 'screen', name: action.next };
  if (action.name === 'open_url' && action.url) out.url = action.url;
  if (PAYLOAD_ACTIONS.has(action.name) && !action.payload)
    out.payload = actionPayload(fields, inherited);
  return out;
};

// Meta no usa una clave genérica "action" en el Flow JSON: los componentes de
// acción (Footer, EmbeddedLink) llevan `on-click-action`, y los de selección
// (RadioButtonsGroup, CheckboxGroup, Dropdown, ChipsSelector, DatePicker)
// llevan `on-select-action` cuando disparan navegación al seleccionar. El
// campo interno del builder sigue llamándose `action` (metadata de
// ComponentPropsEditor); solo la clave de salida del compilador cambia según
// el tipo de componente.
const ON_CLICK_ACTION_TYPES = new Set(['Footer', 'EmbeddedLink']);
const ON_SELECT_ACTION_TYPES = new Set([
  'RadioButtonsGroup',
  'CheckboxGroup',
  'Dropdown',
  'ChipsSelector',
  'DatePicker',
]);

const actionKeyFor = type => {
  if (ON_CLICK_ACTION_TYPES.has(type)) return 'on-click-action';
  if (ON_SELECT_ACTION_TYPES.has(type)) return 'on-select-action';
  return null;
};

const compileComponentProps = (
  type,
  props = {},
  fields = [],
  inherited = []
) => {
  const out = {};
  Object.entries(props).forEach(([key, value]) => {
    if (value === '' || value === undefined || value === null) return;
    if (key === 'action') {
      const compiled = compileAction(value, fields, inherited);
      const actionKey = actionKeyFor(type);
      if (compiled && actionKey) out[actionKey] = compiled;
      return;
    }
    if (key === 'data_source' && Array.isArray(value)) {
      out['data-source'] = value.map(opt => ({ id: opt.id, title: opt.title }));
      return;
    }
    out[mapPropKey(key)] = value;
  });
  return out;
};

const compileComponent = (component, fields, inherited) => ({
  type: component.type,
  ...compileComponentProps(component.type, component.props, fields, inherited),
});

// CheckboxGroup devuelve varias opciones (array); el resto, un texto.
const dataDescriptor = componentType =>
  componentType === 'CheckboxGroup'
    ? { type: 'array', items: { type: 'string' }, __example__: [] }
    : { type: 'string', __example__: 'Ejemplo' };

// Meta exige declarar en `data` cada campo que la pantalla recibe de una
// anterior, con su tipo y un ejemplo.
const screenData = (inherited, previous) => {
  const types = {};
  previous.forEach(s =>
    (s.components || []).forEach(c => {
      if (c.props?.name) types[c.props.name] = c.type;
    })
  );
  const out = {};
  inherited.forEach(f => {
    out[f] = dataDescriptor(types[f]);
  });
  return out;
};

const compileScreen = (screen, previous = []) => {
  const fields = fieldNames(screen);
  const inherited = [...new Set(previous.flatMap(fieldNames))];
  return {
    id: screen.id,
    title: screen.title,
    terminal: !!screen.terminal,
    data: screenData(inherited, previous),
    layout: {
      type: 'SingleColumnLayout',
      // Meta solo resuelve las referencias ${form.campo} si los componentes
      // viven dentro de un Form. Sin esta envoltura el payload llega vacío.
      children: [
        {
          type: 'Form',
          name: FORM_NAME,
          children: (screen.components || []).map(c =>
            compileComponent(c, fields, inherited)
          ),
        },
      ],
    },
  };
};

/**
 * Compila screens_json (formato interno del builder) a Flow JSON 7.3.
 * No valida — solo transforma. La validación vive en useFlowValidation.js
 * (composable) que llama al endpoint /validate del backend.
 */
export const compileFlowJson = (screensJson = []) => {
  const orderedScreens = [...screensJson].sort((a, b) => a.order - b.order);
  return {
    version: FLOW_JSON_VERSION,
    screens: orderedScreens.map((screen, index) =>
      compileScreen(screen, orderedScreens.slice(0, index))
    ),
  };
};
