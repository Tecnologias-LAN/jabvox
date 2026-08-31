import { describe, it, expect } from 'vitest';
import {
  graphFingerprint,
  createAutosaveScheduler,
  AUTOSAVE_MIN_INTERVAL_MS,
} from '../useFlowAutosave';

const graph = (overrides = {}) => ({
  nodes: [
    {
      id: 'a1',
      type: 'jabvox.tag',
      position: { x: 100, y: 200 },
      params: { tag: 'uno', extra: true },
      data: { label: 'Etiquetar' },
    },
  ],
  edges: [{ source: 'a1', target: 'b1', sourceHandle: null }],
  notes: [],
  ...overrides,
});

describe('graphFingerprint', () => {
  it('da la misma huella para objetos distintos con el mismo contenido', () => {
    expect(graphFingerprint(graph())).toBe(graphFingerprint(graph()));
  });

  it('ignora el orden de los pasos, aristas y claves de params', () => {
    const reordered = graph({
      nodes: [
        {
          id: 'a1',
          type: 'jabvox.tag',
          position: { x: 100, y: 200 },
          params: { extra: true, tag: 'uno' },
          data: { label: 'Etiquetar' },
        },
      ],
    });
    expect(graphFingerprint(reordered)).toBe(graphFingerprint(graph()));
  });

  it('ignora micro-desplazamientos al hacer clic sobre un paso', () => {
    const nudged = graph({
      nodes: [{ ...graph().nodes[0], position: { x: 101, y: 200 } }],
    });
    expect(graphFingerprint(nudged)).toBe(graphFingerprint(graph()));
  });

  it('detecta un cambio de parámetro', () => {
    const changed = graph({
      nodes: [{ ...graph().nodes[0], params: { tag: 'dos' } }],
    });
    expect(graphFingerprint(changed)).not.toBe(graphFingerprint(graph()));
  });

  it('detecta una arista nueva y una nota nueva', () => {
    const withEdge = graph({
      edges: [...graph().edges, { source: 'b1', target: 'c1' }],
    });
    expect(graphFingerprint(withEdge)).not.toBe(graphFingerprint(graph()));
    const withNote = graph({
      notes: [
        {
          id: 'note1',
          position: { x: 0, y: 0 },
          width: 280,
          height: 170,
          color: 'amber',
          text: 'hola',
        },
      ],
    });
    expect(graphFingerprint(withNote)).not.toBe(graphFingerprint(graph()));
  });

  it('detecta el cambio de texto de una nota', () => {
    const note = {
      id: 'note1',
      position: { x: 0, y: 0 },
      width: 280,
      height: 170,
      color: 'amber',
      text: 'uno',
    };
    const a = graphFingerprint(graph({ notes: [note] }));
    const b = graphFingerprint(graph({ notes: [{ ...note, text: 'dos' }] }));
    expect(a).not.toBe(b);
  });
});

describe('createAutosaveScheduler', () => {
  it('el primer grafo visto solo fija la referencia, no ensucia', () => {
    const s = createAutosaveScheduler();
    expect(s.noteChange('A', 0)).toBe(false);
    expect(s.isDirty()).toBe(false);
    expect(s.shouldSave(999999)).toBe(false);
  });

  it('no ensucia si la huella no cambió (renders repetidos)', () => {
    const s = createAutosaveScheduler();
    s.markSaved('A', 0);
    expect(s.noteChange('A', 100)).toBe(false);
    expect(s.noteChange('A', 200)).toBe(false);
    expect(s.isDirty()).toBe(false);
  });

  it('guarda tras el debounce cuando el usuario para', () => {
    const s = createAutosaveScheduler({ debounceMs: 2000, maxWaitMs: 10000 });
    s.markSaved('A');
    s.noteChange('B', 1000);
    expect(s.shouldSave(2500)).toBe(false);
    expect(s.shouldSave(3000)).toBe(true);
  });

  it('fuerza el guardado al llegar a maxWait aunque se siga editando', () => {
    const s = createAutosaveScheduler({ debounceMs: 2000, maxWaitMs: 10000 });
    s.markSaved('A');
    // Primer cambio en t=0: maxWait vence en t=10000.
    for (let i = 0; i <= 10; i += 1) {
      const now = i * 1000;
      s.noteChange(`B${i}`, now);
      // Antes de maxWait, tecleando sin pausa, no se guarda.
      if (now < 10000) expect(s.shouldSave(now)).toBe(false);
    }
    expect(s.shouldSave(10000)).toBe(true);
  });

  it('respeta la ventana mínima: no crea una versión por pulsación', () => {
    const s = createAutosaveScheduler({ debounceMs: 2000, maxWaitMs: 10000 });
    s.markSaved('A', 0);
    s.noteChange('B', 1000);
    // Debounce cumplido y maxWait superado, pero la ventana de 60 s manda.
    expect(s.shouldSave(20000)).toBe(false);
    expect(s.shouldSave(AUTOSAVE_MIN_INTERVAL_MS)).toBe(true);
  });

  it('el primer autoguardado tras cargar NO espera la ventana de 60 s', () => {
    const s = createAutosaveScheduler({ debounceMs: 2000, maxWaitMs: 10000 });
    // `load()` marca la referencia SIN sello de tiempo: la ventana aún no corre.
    s.markSaved('A');
    s.noteChange('B', 1000);
    expect(s.shouldSave(3000)).toBe(true);
  });

  it('deshacer hasta el estado guardado deja de pedir guardado', () => {
    const s = createAutosaveScheduler({ debounceMs: 2000, maxWaitMs: 10000 });
    s.markSaved('A');
    s.noteChange('B', 1000);
    expect(s.isDirty()).toBe(true);
    expect(s.noteChange('A', 1500)).toBe(false);
    expect(s.isDirty()).toBe(false);
    expect(s.shouldSave(99999)).toBe(false);
  });

  it('tras guardar queda limpio y arranca una ventana nueva', () => {
    const s = createAutosaveScheduler({ debounceMs: 2000, maxWaitMs: 10000 });
    s.markSaved('A', 0);
    s.noteChange('B', 1000);
    s.markSaved('B', 60000);
    expect(s.isDirty()).toBe(false);
    s.noteChange('C', 61000);
    expect(s.shouldSave(63000)).toBe(false);
    expect(s.shouldSave(120000)).toBe(true);
  });

  it('nextCheckDelay respeta la ventana mínima y no devuelve negativos', () => {
    const s = createAutosaveScheduler({ debounceMs: 2000, maxWaitMs: 10000 });
    expect(s.nextCheckDelay(0)).toBeNull();
    s.markSaved('A', 0);
    s.noteChange('B', 1000);
    expect(s.nextCheckDelay(1000)).toBe(AUTOSAVE_MIN_INTERVAL_MS - 1000);
    expect(s.nextCheckDelay(120000)).toBe(0);
  });
});
