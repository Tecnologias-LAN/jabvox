import { describe, it, expect } from 'vitest';
import {
  createScreen,
  addScreen,
  removeScreen,
  duplicateScreen,
  moveScreen,
  moveScreenUp,
  moveScreenDown,
  reindexScreens,
  addComponentToScreen,
  removeComponentFromScreen,
  updateComponentProps,
  moveComponent,
  uniqueScreenId,
  availableVariablesForScreen,
} from '../screenHelpers';

const baseScreens = () => [
  { id: 'welcome', title: 'Inicio', terminal: false, order: 0, components: [] },
  {
    id: 'rating',
    title: 'Calificación',
    terminal: false,
    order: 1,
    components: [],
  },
  {
    id: 'comment',
    title: 'Comentario',
    terminal: true,
    order: 2,
    components: [],
  },
];

describe('createScreen / uniqueScreenId', () => {
  it('crea la primera pantalla como terminal-false y con order 0', () => {
    const screen = createScreen([], 'Inicio');
    expect(screen.order).toBe(0);
    expect(screen.id).toBe('inicio');
    expect(screen.components).toEqual([]);
  });

  it('genera un id único cuando el slug colisiona', () => {
    const screens = baseScreens();
    const id = uniqueScreenId('Inicio', screens);
    expect(id).not.toBe('welcome');
  });
});

describe('addScreen', () => {
  it('agrega una pantalla nueva al final y reindexa order', () => {
    const screens = addScreen(baseScreens(), 'Nueva');
    expect(screens).toHaveLength(4);
    expect(screens[3].order).toBe(3);
  });
});

describe('removeScreen', () => {
  it('elimina la pantalla y reindexa order de las restantes', () => {
    const screens = removeScreen(baseScreens(), 'rating');
    expect(screens).toHaveLength(2);
    expect(screens.map(s => s.id)).toEqual(['welcome', 'comment']);
    expect(screens[1].order).toBe(1);
  });
});

describe('duplicateScreen', () => {
  it('duplica la pantalla con un id distinto, no terminal, e ids de componente nuevos', () => {
    const screens = [
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: true,
        order: 0,
        components: [
          { id: 'cmp_1', type: 'TextHeading', props: { text: 'Hola' } },
        ],
      },
    ];
    const result = duplicateScreen(screens, 'welcome');
    expect(result).toHaveLength(2);
    const copy = result[1];
    expect(copy.id).not.toBe('welcome');
    expect(copy.terminal).toBe(false);
    expect(copy.components[0].id).not.toBe('cmp_1');
    expect(copy.components[0].props.text).toBe('Hola');
  });

  it('no hace nada si el id no existe', () => {
    const screens = baseScreens();
    expect(duplicateScreen(screens, 'no_existe')).toBe(screens);
  });
});

describe('moveScreen / moveScreenUp / moveScreenDown', () => {
  it('mueve una pantalla de una posición a otra y reindexa', () => {
    const screens = moveScreen(baseScreens(), 2, 0);
    expect(screens.map(s => s.id)).toEqual(['comment', 'welcome', 'rating']);
    expect(screens.map(s => s.order)).toEqual([0, 1, 2]);
  });

  it('moveScreenUp no hace nada en la primera posición', () => {
    const screens = baseScreens();
    expect(moveScreenUp(screens, 'welcome')).toBe(screens);
  });

  it('moveScreenDown no hace nada en la última posición', () => {
    const screens = baseScreens();
    expect(moveScreenDown(screens, 'comment')).toBe(screens);
  });

  it('moveScreenUp sube una pantalla intermedia', () => {
    const result = moveScreenUp(baseScreens(), 'comment');
    expect(result.map(s => s.id)).toEqual(['welcome', 'comment', 'rating']);
  });

  it('moveScreenDown baja una pantalla intermedia', () => {
    const result = moveScreenDown(baseScreens(), 'welcome');
    expect(result.map(s => s.id)).toEqual(['rating', 'welcome', 'comment']);
  });
});

describe('reindexScreens', () => {
  it('reasigna order 0..n-1 según la posición del array', () => {
    const screens = [
      { id: 'a', order: 5 },
      { id: 'b', order: 1 },
    ];
    expect(reindexScreens(screens).map(s => s.order)).toEqual([0, 1]);
  });
});

describe('componentes dentro de una screen', () => {
  it('agrega un componente a la screen correcta', () => {
    const screens = baseScreens();
    const result = addComponentToScreen(screens, 'welcome', {
      id: 'cmp_1',
      type: 'TextHeading',
      props: { text: 'Hola' },
    });
    expect(result.find(s => s.id === 'welcome').components).toHaveLength(1);
    expect(result.find(s => s.id === 'rating').components).toHaveLength(0);
  });

  it('elimina un componente por id', () => {
    let screens = addComponentToScreen(baseScreens(), 'welcome', {
      id: 'cmp_1',
      type: 'TextHeading',
      props: {},
    });
    screens = removeComponentFromScreen(screens, 'welcome', 'cmp_1');
    expect(screens.find(s => s.id === 'welcome').components).toHaveLength(0);
  });

  it('actualiza props de un componente sin afectar otros campos', () => {
    let screens = addComponentToScreen(baseScreens(), 'welcome', {
      id: 'cmp_1',
      type: 'TextHeading',
      props: { text: 'Hola', extra: 'x' },
    });
    screens = updateComponentProps(screens, 'welcome', 'cmp_1', {
      text: 'Nuevo',
    });
    const cmp = screens.find(s => s.id === 'welcome').components[0];
    expect(cmp.props.text).toBe('Nuevo');
    expect(cmp.props.extra).toBe('x');
  });

  it('reordena componentes dentro de una screen', () => {
    let screens = addComponentToScreen(baseScreens(), 'welcome', {
      id: 'cmp_1',
      type: 'TextHeading',
      props: {},
    });
    screens = addComponentToScreen(screens, 'welcome', {
      id: 'cmp_2',
      type: 'TextBody',
      props: {},
    });
    screens = moveComponent(screens, 'welcome', 0, 1);
    const ids = screens.find(s => s.id === 'welcome').components.map(c => c.id);
    expect(ids).toEqual(['cmp_2', 'cmp_1']);
  });
});

describe('availableVariablesForScreen', () => {
  it('solo devuelve variables de pantallas anteriores (por order), nunca de la propia o posteriores', () => {
    const screens = [
      {
        id: 'welcome',
        title: 'Inicio',
        order: 0,
        components: [
          { id: 'c1', type: 'TextInput', props: { name: 'nombre' } },
        ],
      },
      {
        id: 'rating',
        title: 'Calificación',
        order: 1,
        components: [
          {
            id: 'c2',
            type: 'RadioButtonsGroup',
            props: { name: 'calificacion' },
          },
        ],
      },
      {
        id: 'comment',
        title: 'Comentario',
        order: 2,
        components: [
          { id: 'c3', type: 'TextArea', props: { name: 'comentario' } },
        ],
      },
    ];

    const varsForRating = availableVariablesForScreen(screens, 'rating');
    expect(varsForRating).toHaveLength(1);
    expect(varsForRating[0].name).toBe('nombre');

    const varsForComment = availableVariablesForScreen(screens, 'comment');
    expect(varsForComment.map(v => v.name)).toEqual(['nombre', 'calificacion']);

    const varsForWelcome = availableVariablesForScreen(screens, 'welcome');
    expect(varsForWelcome).toHaveLength(0);
  });

  it('ignora componentes sin `name` (textos estáticos)', () => {
    const screens = [
      {
        id: 'welcome',
        order: 0,
        components: [
          { id: 'c1', type: 'TextHeading', props: { text: 'Hola' } },
        ],
      },
      { id: 'next', order: 1, components: [] },
    ];
    expect(availableVariablesForScreen(screens, 'next')).toHaveLength(0);
  });
});
