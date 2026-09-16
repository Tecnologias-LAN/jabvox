// Helpers puros para manipular screens_json (crear/duplicar/eliminar/
// reordenar/slug) — separados de los componentes Vue para poder testear la
// lógica sin montar nada (mismo criterio que useFlowAutosave.js en
// Automations: funciones puras + specs con describe/it/expect).

let idCounter = 0;
// Contador in-memory para generar ids únicos de screen/componente en una
// misma sesión de edición. Se resetea entre tests con resetIdCounter().
export const resetIdCounter = () => {
  idCounter = 0;
};

const nextId = prefix => {
  idCounter += 1;
  return `${prefix}_${Date.now().toString(36)}_${idCounter}`;
};

const slugify = text =>
  (text || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40) || 'screen';

/** Genera un id de screen único (slug + sufijo si colisiona) dentro de un flow. */
export const uniqueScreenId = (title, existingScreens = []) => {
  const base = slugify(title);
  const existingIds = new Set(existingScreens.map(s => s.id));
  if (!existingIds.has(base)) return base;
  let n = 2;
  while (existingIds.has(`${base}_${n}`)) n += 1;
  return `${base}_${n}`;
};

export const createComponentId = () => nextId('cmp');

/** Crea una screen nueva (vacía) con el siguiente `order` disponible. */
export const createScreen = (screens = [], title = 'Nueva pantalla') => ({
  id: uniqueScreenId(title, screens),
  title,
  terminal: screens.length === 0,
  order: screens.length,
  components: [],
});

/** Reindexa `order` 0..n-1 según la posición actual del array. */
export const reindexScreens = screens =>
  screens.map((s, i) => ({ ...s, order: i }));

export const addScreen = (screens, title) =>
  reindexScreens([...screens, createScreen(screens, title)]);

export const removeScreen = (screens, screenId) =>
  reindexScreens(screens.filter(s => s.id !== screenId));

export const duplicateScreen = (screens, screenId) => {
  const source = screens.find(s => s.id === screenId);
  if (!source) return screens;
  const copy = {
    ...source,
    id: uniqueScreenId(`${source.title}_copy`, screens),
    title: `${source.title} (copia)`,
    terminal: false,
    components: source.components.map(c => ({
      ...c,
      id: createComponentId(),
      props: { ...c.props },
    })),
  };
  const index = screens.findIndex(s => s.id === screenId);
  const next = [...screens];
  next.splice(index + 1, 0, copy);
  return reindexScreens(next);
};

/** Mueve una screen de `fromIndex` a `toIndex` (usado por drag & drop y por los botones subir/bajar). */
export const moveScreen = (screens, fromIndex, toIndex) => {
  if (
    fromIndex === toIndex ||
    fromIndex < 0 ||
    toIndex < 0 ||
    fromIndex >= screens.length ||
    toIndex >= screens.length
  ) {
    return screens;
  }
  const next = [...screens];
  const [moved] = next.splice(fromIndex, 1);
  next.splice(toIndex, 0, moved);
  return reindexScreens(next);
};

export const moveScreenUp = (screens, screenId) => {
  const index = screens.findIndex(s => s.id === screenId);
  if (index <= 0) return screens;
  return moveScreen(screens, index, index - 1);
};

export const moveScreenDown = (screens, screenId) => {
  const index = screens.findIndex(s => s.id === screenId);
  if (index === -1 || index >= screens.length - 1) return screens;
  return moveScreen(screens, index, index + 1);
};

export const addComponentToScreen = (screens, screenId, component) =>
  screens.map(s =>
    s.id === screenId ? { ...s, components: [...s.components, component] } : s
  );

export const removeComponentFromScreen = (screens, screenId, componentId) =>
  screens.map(s =>
    s.id === screenId
      ? { ...s, components: s.components.filter(c => c.id !== componentId) }
      : s
  );

export const updateComponentProps = (screens, screenId, componentId, props) =>
  screens.map(s =>
    s.id === screenId
      ? {
          ...s,
          components: s.components.map(c =>
            c.id === componentId ? { ...c, props: { ...c.props, ...props } } : c
          ),
        }
      : s
  );

export const moveComponent = (screens, screenId, fromIndex, toIndex) =>
  screens.map(s => {
    if (s.id !== screenId) return s;
    if (
      fromIndex === toIndex ||
      fromIndex < 0 ||
      toIndex < 0 ||
      fromIndex >= s.components.length ||
      toIndex >= s.components.length
    ) {
      return s;
    }
    const next = [...s.components];
    const [moved] = next.splice(fromIndex, 1);
    next.splice(toIndex, 0, moved);
    return { ...s, components: next };
  });

/**
 * Para el VariablePicker (sección 4.4): dado un screenId, devuelve los
 * `name` de componentes con nombre (inputs/choice) de pantallas ANTERIORES
 * en el flujo (por `order`), nunca de la propia pantalla o de una posterior
 * — evita ciclos y referencias rotas, tal como exige el Validator backend.
 */
export const availableVariablesForScreen = (screens, screenId) => {
  const target = screens.find(s => s.id === screenId);
  if (!target) return [];
  return screens
    .filter(s => s.order < target.order)
    .flatMap(s =>
      (s.components || [])
        .filter(c => c.props?.name)
        .map(c => ({
          screenId: s.id,
          screenTitle: s.title,
          name: c.props.name,
          type: c.type,
          reference: `\${screen.${s.id}.form.${c.props.name}}`,
        }))
    );
};

// Variables de sistema (contacto) disponibles en la primera pantalla —
// sección 4.4: se inyectan al ENVIAR el Flow vía flow_action_data.
// Sintaxis literal del Flow JSON de Meta ("$" + "{...}"), no interpolación de
// JS — se arma con String.fromCharCode para el símbolo "$" y así el linter
// (no-template-curly-in-string / no-useless-concat) no lo confunda con un
// template literal roto.
const DOLLAR = String.fromCharCode(36);
const systemVariableRef = path => `${DOLLAR}{${path}}`;

export const SYSTEM_VARIABLES = [
  {
    key: 'contact.name',
    reference: systemVariableRef('data.nombre'),
    label: 'Nombre del contacto',
  },
  {
    key: 'contact.phone_number',
    reference: systemVariableRef('data.telefono'),
    label: 'Teléfono del contacto',
  },
  {
    key: 'contact.email',
    reference: systemVariableRef('data.email'),
    label: 'Email del contacto',
  },
];
