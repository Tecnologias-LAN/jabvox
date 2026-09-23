import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import AiBudgetSettings from '../AiBudgetSettings.vue';

// La pantalla se rediseñó a tarjetas + filas flex (antes era una <table>, que se desbordaba
// en móvil). Estas pruebas fijan lo que no debe volver a romperse: que no haya tabla, que
// las columnas secundarias se oculten en pantallas pequeñas, y que "sin tope" no se muestre
// como $0.00 (que significaría lo contrario: agotado).

const mockGet = vi.fn();
const mockKeys = vi.fn();

vi.mock('dashboard/api/jabvox/aiBudget', () => ({
  aiBudgetAPI: {
    get: (...a) => mockGet(...a),
    keys: (...a) => mockKeys(...a),
    createKey: vi.fn(),
    blockKey: vi.fn(),
    unblockKey: vi.fn(),
    updateKey: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const stubs = {
  Button: {
    props: ['label', 'icon', 'color'],
    template: '<button>{{ label }}</button>',
  },
  Input: { props: ['modelValue', 'label'], template: '<input />' },
  Label: {
    props: ['label', 'color'],
    template: '<span class="label">{{ label }}</span>',
  },
  Spinner: { template: '<div class="spinner" />' },
  Dialog: { template: '<div><slot /></div>' },
};

const mountWith = async (balance, keys = [], models = {}) => {
  mockGet.mockResolvedValue({ data: balance });
  mockKeys.mockResolvedValue({
    data: {
      keys,
      available_models: models.available || [],
      team_models: models.team || [],
    },
  });
  const wrapper = mount(AiBudgetSettings, {
    global: {
      stubs,
      mocks: { $t: k => k },
      plugins: [],
      provide: {},
    },
  });
  // Deja resolver las promesas de onMounted.
  await new Promise(resolve => {
    setTimeout(resolve, 0);
  });
  await wrapper.vm.$nextTick();
  return wrapper;
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe('AiBudgetSettings — layout', () => {
  it('no usa <table>: se desbordaba en móvil', async () => {
    const wrapper = await mountWith(
      { connected: true, total_budget_usd: 20, cached_spend_usd: 5 },
      [{ alias: 'produccion', token_id: 'tok-1', spend: 1, max_budget: 10 }]
    );

    expect(wrapper.find('table').exists()).toBe(false);
  });

  it('el contenedor centra y limita el ancho, con gutter en móvil', async () => {
    const wrapper = await mountWith({ connected: true, total_budget_usd: 20 });
    const html = wrapper.html();

    expect(html).toContain('max-w-4xl');
    expect(html).toContain('mx-auto');
    // Padding lateral que crece con el viewport.
    expect(html).toContain('px-4');
    expect(html).toContain('sm:px-6');
  });

  it('los KPIs apilan en 1 columna y se expanden a 4 en escritorio', async () => {
    const wrapper = await mountWith({ connected: true, total_budget_usd: 20 });
    const html = wrapper.html();

    expect(html).toContain('grid-cols-1');
    expect(html).toContain('sm:grid-cols-2');
    expect(html).toContain('lg:grid-cols-4');
  });

  it('oculta columnas secundarias de las keys en pantallas pequeñas', async () => {
    const wrapper = await mountWith({ connected: true, total_budget_usd: 20 }, [
      { alias: 'k1', token_id: 'tok-1', spend: 1, max_budget: 10 },
    ]);
    const html = wrapper.html();

    // Tope aparece desde sm; gasto desde md; en móvil van resumidos bajo el nombre.
    expect(html).toContain('hidden sm:block');
    expect(html).toContain('hidden md:block');
    expect(html).toContain('sm:hidden');
  });
});

describe('AiBudgetSettings — estados', () => {
  it('muestra el aviso de "no aprovisionado" cuando no hay team', async () => {
    const wrapper = await mountWith({ connected: false });

    expect(wrapper.html()).toContain('does not have an AI balance provisioned');
    // El formulario de crear key no debe aparecer sin team.
    expect(wrapper.html()).not.toContain('Create key');
  });

  it('un team sin tope muestra "sin límite", nunca $0.00', async () => {
    const wrapper = await mountWith({
      connected: true,
      unlimited: true,
      total_budget_usd: 0,
      remaining_usd: null,
      cached_spend_usd: 6.22,
    });
    const html = wrapper.html();

    // Tope y restante salen como "sin límite" (dos tarjetas), no como $0.00.
    expect(html.match(/Unlimited/g)).toHaveLength(2);
    // El gasto real sí se muestra tal cual.
    expect(html).toContain('$6.22');
    // El restante NO debe ser un negativo del gasto (era "-$6.22" antes del fix).
    expect(html).not.toContain('-$6.22');
  });

  it('no dibuja barra de consumo si el tope es ilimitado', async () => {
    const wrapper = await mountWith({
      connected: true,
      unlimited: true,
      total_budget_usd: 0,
      cached_spend_usd: 3,
    });

    expect(wrapper.html()).not.toContain('Usage');
  });

  it('dibuja la barra con el porcentaje correcto cuando hay tope', async () => {
    const wrapper = await mountWith({
      connected: true,
      total_budget_usd: 20,
      cached_spend_usd: 5,
    });

    expect(wrapper.html()).toContain('Usage');
    expect(wrapper.html()).toContain('width: 25%');
  });

  it('pinta la barra en rojo cuando el consumo supera el 90%', async () => {
    const wrapper = await mountWith({
      connected: true,
      total_budget_usd: 10,
      cached_spend_usd: 9.5,
    });

    expect(wrapper.html()).toContain('bg-n-ruby-9');
  });

  it('muestra los modelos asignados a cada key', async () => {
    const wrapper = await mountWith(
      { connected: true, total_budget_usd: 20 },
      [{ alias: 'k1', token_id: 'tok-1', models: ['gpt-4o', 'claude-sonnet'] }],
      { available: ['gpt-4o', 'claude-sonnet', 'otro'] }
    );

    expect(wrapper.html()).toContain('gpt-4o, claude-sonnet');
  });

  it('solo ofrece los modelos del team cuando el team está restringido', async () => {
    const wrapper = await mountWith(
      { connected: true, total_budget_usd: 20 },
      [{ alias: 'k1', token_id: 'tok-1' }],
      { available: ['gpt-4o', 'claude-sonnet', 'otro'], team: ['gpt-4o'] }
    );

    // El team limita a gpt-4o: los demás no deben poder asignarse.
    expect(wrapper.vm.selectableModels).toEqual(['gpt-4o']);
  });

  it('ofrece todos los modelos del proveedor si el team no restringe', async () => {
    const wrapper = await mountWith(
      { connected: true, total_budget_usd: 20 },
      [{ alias: 'k1', token_id: 'tok-1' }],
      { available: ['gpt-4o', 'claude-sonnet'], team: [] }
    );

    expect(wrapper.vm.selectableModels).toEqual(['gpt-4o', 'claude-sonnet']);
  });

  it('toggleModel añade y quita modelos de la selección', async () => {
    const wrapper = await mountWith({ connected: true, total_budget_usd: 20 });
    const list = [];

    wrapper.vm.toggleModel(list, 'gpt-4o');
    expect(list).toEqual(['gpt-4o']);

    wrapper.vm.toggleModel(list, 'gpt-4o');
    expect(list).toEqual([]);
  });

  it('si las keys fallan, el saldo sigue visible y avisa de forma concreta', async () => {
    // El saldo carga bien pero /keys falla (proveedor lento). Antes decía "no se pudo
    // cargar el saldo" con el saldo delante, y dejaba la pantalla a medias.
    mockGet.mockResolvedValue({
      data: { connected: true, total_budget_usd: 20, cached_spend_usd: 5 },
    });
    mockKeys.mockRejectedValue(new Error('502'));

    const wrapper = mount(AiBudgetSettings, {
      global: { stubs, mocks: { $t: k => k }, plugins: [], provide: {} },
    });
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.keysError).toBe(true);
    // El saldo se pintó igualmente.
    expect(wrapper.html()).toContain('$20.00');
    expect(wrapper.html()).toContain('did not respond in time');
  });

  it('filtra las keys por nombre', async () => {
    const wrapper = await mountWith({ connected: true, total_budget_usd: 20 }, [
      { alias: 'produccion', token_id: 'tok-1' },
      { alias: 'staging', token_id: 'tok-2' },
    ]);

    wrapper.vm.search = 'stag';
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.filteredKeys).toHaveLength(1);
    expect(wrapper.vm.filteredKeys[0].alias).toBe('staging');
  });
});
