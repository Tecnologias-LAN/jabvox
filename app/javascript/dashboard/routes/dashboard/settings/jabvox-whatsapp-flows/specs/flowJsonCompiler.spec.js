/* eslint-disable no-template-curly-in-string --
   "${form.campo}" es la sintaxis literal de referencia de Meta en el Flow JSON,
   no una plantilla de JavaScript sin interpolar. */
import { describe, it, expect } from 'vitest';
import { compileFlowJson } from '../flowJsonCompiler';

// Los componentes van dentro de un Form: Meta solo resuelve ${form.campo}
// dentro de él, y sin eso la respuesta del formulario llega vacía.
const childrenOf = screen => {
  expect(screen.layout.children[0].type).toBe('Form');
  return screen.layout.children[0].children;
};

describe('compileFlowJson', () => {
  it('compila a la versión 7.3 con las screens ordenadas por `order`', () => {
    const screensJson = [
      {
        id: 'comment',
        title: 'Comentario',
        terminal: true,
        order: 1,
        components: [],
      },
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: false,
        order: 0,
        components: [],
      },
    ];
    const result = compileFlowJson(screensJson);
    expect(result.version).toBe('7.3');
    expect(result.screens.map(s => s.id)).toEqual(['welcome', 'comment']);
  });

  it('usa SingleColumnLayout y mapea los componentes como children', () => {
    const result = compileFlowJson([
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: false,
        order: 0,
        components: [
          { id: 'cmp_1', type: 'TextHeading', props: { text: 'Hola' } },
        ],
      },
    ]);
    expect(result.screens[0].layout.type).toBe('SingleColumnLayout');
    expect(result.screens[0].layout.children).toHaveLength(1);
    expect(result.screens[0].layout.children[0].type).toBe('Form');
    expect(childrenOf(result.screens[0])).toHaveLength(1);
    expect(childrenOf(result.screens[0])[0].type).toBe('TextHeading');
    expect(childrenOf(result.screens[0])[0].text).toBe('Hola');
  });

  it('mapea data_source a la clave kebab-case data-source', () => {
    const result = compileFlowJson([
      {
        id: 'rating',
        title: 'Calificación',
        terminal: false,
        order: 0,
        components: [
          {
            id: 'cmp_1',
            type: 'RadioButtonsGroup',
            props: {
              name: 'calificacion',
              label: '¿Cómo calificas?',
              data_source: [{ id: 'excelente', title: 'Excelente' }],
              required: true,
            },
          },
        ],
      },
    ]);
    const compiled = childrenOf(result.screens[0])[0];
    expect(compiled['data-source']).toEqual([
      { id: 'excelente', title: 'Excelente' },
    ]);
    expect(compiled.data_source).toBeUndefined();
    expect(compiled.name).toBe('calificacion');
  });

  it('compila la acción navigate de un Footer como on-click-action con next como screen ref', () => {
    const result = compileFlowJson([
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: false,
        order: 0,
        components: [
          {
            id: 'cmp_footer',
            type: 'Footer',
            props: {
              label: 'Siguiente',
              action: { name: 'navigate', next: 'rating' },
            },
          },
        ],
      },
    ]);
    const footer = childrenOf(result.screens[0])[0];
    expect(footer.action).toBeUndefined();
    expect(footer['on-click-action'].name).toBe('navigate');
    expect(footer['on-click-action'].next).toEqual({
      type: 'screen',
      name: 'rating',
    });
  });

  it('compila la acción complete sin next como on-click-action', () => {
    const result = compileFlowJson([
      {
        id: 'comment',
        title: 'Comentario',
        terminal: true,
        order: 0,
        components: [
          {
            id: 'cmp_footer',
            type: 'Footer',
            props: { label: 'Enviar', action: { name: 'complete' } },
          },
        ],
      },
    ]);
    const footer = childrenOf(result.screens[0])[0];
    expect(footer['on-click-action'].name).toBe('complete');
    expect(footer['on-click-action'].next).toBeUndefined();
  });

  // El payload es lo que hace que Meta devuelva las respuestas: sin él manda un
  // nfm_reply con el flow_token y nada más, que es el bug que se corrigió.
  it('declara en el payload del complete los campos de la propia pantalla', () => {
    const result = compileFlowJson([
      {
        id: 'unica',
        title: 'Única',
        terminal: true,
        order: 0,
        components: [
          { type: 'TextInput', props: { name: 'comentario', label: 'C' } },
          {
            type: 'Footer',
            props: { label: 'Enviar', action: { name: 'complete' } },
          },
        ],
      },
    ]);
    const footer = childrenOf(result.screens[0])[1];
    expect(footer['on-click-action'].payload).toEqual({
      comentario: '${form.comentario}',
    });
  });

  it('arrastra las respuestas de pantallas anteriores hasta el complete final', () => {
    const result = compileFlowJson([
      {
        id: 'uno',
        title: 'Uno',
        order: 0,
        components: [
          {
            type: 'CheckboxGroup',
            props: {
              name: 'servicios',
              label: 'S',
              data_source: [{ id: 'a', title: 'A' }],
            },
          },
          {
            type: 'Footer',
            props: {
              label: 'Siguiente',
              action: { name: 'navigate', next: 'dos' },
            },
          },
        ],
      },
      {
        id: 'dos',
        title: 'Dos',
        order: 1,
        terminal: true,
        components: [
          { type: 'TextInput', props: { name: 'comentario', label: 'C' } },
          {
            type: 'Footer',
            props: { label: 'Enviar', action: { name: 'complete' } },
          },
        ],
      },
    ]);
    const [primera, ultima] = result.screens;

    // La primera reenvía lo suyo al navegar…
    expect(childrenOf(primera)[1]['on-click-action'].payload).toEqual({
      servicios: '${form.servicios}',
    });
    // …la segunda lo declara en su `data` (array, por ser CheckboxGroup)…
    expect(ultima.data.servicios.type).toBe('array');
    // …y el complete final devuelve lo propio y lo heredado.
    expect(childrenOf(ultima)[1]['on-click-action'].payload).toEqual({
      comentario: '${form.comentario}',
      servicios: '${data.servicios}',
    });
  });

  it('compila la acción de un EmbeddedLink como on-click-action', () => {
    const result = compileFlowJson([
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: false,
        order: 0,
        components: [
          {
            id: 'cmp_link',
            type: 'EmbeddedLink',
            props: {
              text: 'Ver términos',
              action: { name: 'open_url', url: 'https://example.com' },
            },
          },
        ],
      },
    ]);
    const link = childrenOf(result.screens[0])[0];
    expect(link['on-click-action']).toEqual({
      name: 'open_url',
      url: 'https://example.com',
    });
  });

  it('omite props vacías/undefined del componente compilado', () => {
    const result = compileFlowJson([
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: false,
        order: 0,
        components: [
          {
            id: 'cmp_1',
            type: 'TextInput',
            props: { name: 'x', label: 'X', init_value: '' },
          },
        ],
      },
    ]);
    const compiled = childrenOf(result.screens[0])[0];
    expect(compiled['init-value']).toBeUndefined();
  });
});
