import { ref } from 'vue';
import { describe, it, expect } from 'vitest';
import { useFlowJsonPreview } from '../useFlowJsonPreview';

describe('useFlowJsonPreview', () => {
  it('compiles an empty screens array to a valid-shaped empty flow', () => {
    const { compiledJson, localChecks } = useFlowJsonPreview(ref([]));
    expect(compiledJson.value.screens).toEqual([]);
    expect(localChecks.value.hasScreens).toBe(false);
  });

  it('produces a formatted JSON string that matches the compiled object', () => {
    const screens = ref([
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: true,
        order: 0,
        components: [],
      },
    ]);
    const { compiledJson, compiledJsonString } = useFlowJsonPreview(screens);
    expect(compiledJsonString.value).toBe(
      JSON.stringify(compiledJson.value, null, 2)
    );
  });

  it('localChecks flags a terminal screen and a Footer-less screen correctly', () => {
    const screens = ref([
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: true,
        order: 0,
        components: [{ id: 'c1', type: 'TextHeading', props: {} }],
      },
    ]);
    const { localChecks } = useFlowJsonPreview(screens);
    expect(localChecks.value.hasTerminalScreen).toBe(true);
    expect(localChecks.value.allScreensHaveFooter).toBe(false);
  });

  it('localChecks.allScreensHaveFooter is true when every screen has a Footer', () => {
    const screens = ref([
      {
        id: 'welcome',
        title: 'Inicio',
        terminal: true,
        order: 0,
        components: [
          { id: 'c1', type: 'Footer', props: { action: { name: 'complete' } } },
        ],
      },
    ]);
    const { localChecks } = useFlowJsonPreview(screens);
    expect(localChecks.value.allScreensHaveFooter).toBe(true);
  });

  it('reacts to screens changing (recomputes on ref update)', () => {
    const screens = ref([]);
    const { localChecks } = useFlowJsonPreview(screens);
    expect(localChecks.value.hasScreens).toBe(false);
    screens.value = [
      { id: 'a', title: 'A', terminal: false, order: 0, components: [] },
    ];
    expect(localChecks.value.hasScreens).toBe(true);
  });
});
