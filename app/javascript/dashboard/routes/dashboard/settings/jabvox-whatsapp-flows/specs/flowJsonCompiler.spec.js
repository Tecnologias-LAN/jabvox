import { describe, it, expect } from 'vitest';
import { compileFlowJson } from '../flowJsonCompiler';

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
    expect(result.screens[0].layout.children[0].type).toBe('TextHeading');
    expect(result.screens[0].layout.children[0].text).toBe('Hola');
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
    const compiled = result.screens[0].layout.children[0];
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
    const footer = result.screens[0].layout.children[0];
    expect(footer.action).toBeUndefined();
    expect(footer['on-click-action']).toEqual({
      name: 'navigate',
      next: { type: 'screen', name: 'rating' },
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
    const footer = result.screens[0].layout.children[0];
    expect(footer['on-click-action']).toEqual({ name: 'complete' });
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
    const link = result.screens[0].layout.children[0];
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
    const compiled = result.screens[0].layout.children[0];
    expect(compiled['init-value']).toBeUndefined();
  });
});
