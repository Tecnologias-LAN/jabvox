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

const compileAction = action => {
  if (!action || !action.name) return undefined;
  const out = { name: action.name };
  if (action.name === 'navigate' && action.next)
    out.next = { type: 'screen', name: action.next };
  if (action.name === 'open_url' && action.url) out.url = action.url;
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

const compileComponentProps = (type, props = {}) => {
  const out = {};
  Object.entries(props).forEach(([key, value]) => {
    if (value === '' || value === undefined || value === null) return;
    if (key === 'action') {
      const compiled = compileAction(value);
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

const compileComponent = component => ({
  type: component.type,
  ...compileComponentProps(component.type, component.props),
});

const compileScreen = screen => ({
  id: screen.id,
  title: screen.title,
  terminal: !!screen.terminal,
  data: {},
  layout: {
    type: 'SingleColumnLayout',
    children: (screen.components || []).map(compileComponent),
  },
});

/**
 * Compila screens_json (formato interno del builder) a Flow JSON 7.3.
 * No valida — solo transforma. La validación vive en useFlowValidation.js
 * (composable) que llama al endpoint /validate del backend.
 */
export const compileFlowJson = (screensJson = []) => {
  const orderedScreens = [...screensJson].sort((a, b) => a.order - b.order);
  return {
    version: FLOW_JSON_VERSION,
    screens: orderedScreens.map(compileScreen),
  };
};
