import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import VersionHistory from '../VersionHistory.vue';

vi.mock('vue-i18n', () => ({
  // Se devuelve la clave para poder afirmar sobre ella sin depender del idioma.
  useI18n: () => ({
    t: (k, params) => (params ? `${k}:${JSON.stringify(params)}` : k),
  }),
}));

const listVersions = vi.fn();
const getVersion = vi.fn();
const restoreVersion = vi.fn();

vi.mock('dashboard/api/jabvox/flows', () => ({
  flowsAPI: {
    listVersions: (...a) => listVersions(...a),
    getVersion: (...a) => getVersion(...a),
    restoreVersion: (...a) => restoreVersion(...a),
  },
}));

const VERSIONS = [
  {
    id: '3',
    version: 3,
    createdAt: '2026-08-30T10:00:00Z',
    createdByName: 'Ana',
    nodeCount: 4,
    edgeCount: 3,
    isCurrent: true,
  },
  {
    id: '2',
    version: 2,
    createdAt: '2026-08-29T10:00:00Z',
    createdByName: null,
    nodeCount: 2,
    edgeCount: 1,
    isCurrent: false,
  },
];

const mountPanel = () => mount(VersionHistory, { props: { flowId: '7' } });

describe('VersionHistory', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    listVersions.mockResolvedValue({ data: VERSIONS });
  });

  it('lista las versiones con número, autor y marca de actual', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    const text = wrapper.text();
    expect(listVersions).toHaveBeenCalledWith('7');
    expect(text).toContain('Ana');
    // Sin autor conocido se usa la clave de respaldo, no una cadena cruda.
    expect(text).toContain('VERSIONS.UNKNOWN_AUTHOR');
    expect(text).toContain('VERSIONS.CURRENT');
  });

  it('muestra el estado vacío cuando no hay versiones', async () => {
    listVersions.mockResolvedValue({ data: [] });
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.text()).toContain('VERSIONS.EMPTY');
  });

  it('muestra el error de la API en vez de una lista en blanco', async () => {
    listVersions.mockRejectedValue({
      response: { data: { error: 'Sin permiso' } },
    });
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.text()).toContain('Sin permiso');
  });

  it('previsualiza una versión sin restaurarla', async () => {
    getVersion.mockResolvedValue({
      data: {
        version: 2,
        graph: {
          nodes: [
            { id: 'tag1', type: 'jabvox.tag', data: { label: 'Etiquetar' } },
          ],
        },
      },
    });
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper
      .findAll('[title="JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.PREVIEW"]')[1]
      .trigger('click');
    await flushPromises();

    expect(getVersion).toHaveBeenCalledWith('7', 2);
    expect(wrapper.text()).toContain('Etiquetar');
    // Previsualizar NO restaura.
    expect(restoreVersion).not.toHaveBeenCalled();
  });

  it('la versión actual no ofrece restaurar', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    const buttons = wrapper.findAll(
      '[title="JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE"]'
    );
    // Solo la versión 2; la 3 es la actual.
    expect(buttons.length).toBe(1);
  });

  it('restaurar pide confirmación en un modal antes de llamar a la API', async () => {
    restoreVersion.mockResolvedValue({ data: { version: 4 } });
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper
      .find('[title="JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE"]')
      .trigger('click');
    await flushPromises();

    // El modal está abierto y explica qué se pierde; todavía no se llamó a la API.
    expect(wrapper.text()).toContain('VERSIONS.RESTORE_TITLE');
    expect(wrapper.text()).toContain('VERSIONS.RESTORE_LOSES');
    expect(restoreVersion).not.toHaveBeenCalled();

    // El botón de confirmar es el último del modal.
    const confirm = wrapper
      .findAll('button')
      .filter(b => b.text().includes('VERSIONS.RESTORE'))
      .pop();
    await confirm.trigger('click');
    await flushPromises();

    expect(restoreVersion).toHaveBeenCalledWith('7', 2);
    expect(wrapper.emitted('restored')).toBeTruthy();
  });

  it('cancelar el modal no restaura nada', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper
      .find('[title="JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE"]')
      .trigger('click');
    await flushPromises();

    const cancel = wrapper
      .findAll('button')
      .filter(b => b.text().includes('FORM.CANCEL'))
      .pop();
    await cancel.trigger('click');
    await flushPromises();

    expect(restoreVersion).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain('VERSIONS.RESTORE_TITLE');
  });
});
