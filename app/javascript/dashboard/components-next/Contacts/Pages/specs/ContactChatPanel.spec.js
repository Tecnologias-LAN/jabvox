import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import ContactChatPanel from '../ContactChatPanel.vue';

// El panel del chat de la ficha del contacto tiene un contrato frágil con el store: hay que
// activar la conversación NORMALIZADA de `allConversations` (la que trae `messages`), no un
// objeto construido a mano. Si se pasa `{ id }` a secas, `setActiveChat` lanza por dentro,
// su catch se lo traga y MessagesView se queda cargando indefinidamente.
//
// MessagesView se sustituye por un stub porque aquí solo interesa lo que se le pide al store.
const CONVERSATION = {
  id: 8,
  display_id: 8,
  status: 'open',
  inbox: { id: 12, name: 'Ventas', channel_type: 'Channel::WebWidget' },
  unread_count: 0,
};

// Lo que el store devuelve por `getAllConversations`: con `messages`, como en producción.
const STORED = { id: 8, messages: [{ id: 100 }], status: 'open' };

const dispatch = vi.fn();
const getters = {
  getSelectedChat: { id: 8 },
  getAllConversations: [STORED],
};

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: name => ({ value: getters[name] }),
}));

const mountPanel = (conversations = [CONVERSATION]) =>
  mount(ContactChatPanel, {
    props: { conversations },
    global: {
      stubs: {
        MessagesView: { template: '<div class="messages-view" />' },
        Spinner: true,
      },
      mocks: { $t: key => key },
      plugins: [
        {
          install: app => {
            app.config.globalProperties.$t = key => key;
          },
        },
      ],
    },
  });

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

// Deja correr las promesas pendientes del onMounted/watch antes de comprobar.
const flush = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });

describe('ContactChatPanel', () => {
  beforeEach(() => {
    dispatch.mockReset();
    dispatch.mockResolvedValue(undefined);
  });

  it('activa la conversación normalizada del store, no un objeto improvisado', async () => {
    mountPanel();
    await flush();

    expect(dispatch).toHaveBeenCalledWith('getConversation', 8);
    expect(dispatch).toHaveBeenCalledWith('setActiveChat', { data: STORED });
    // El objeto activado DEBE traer messages: es lo que setActiveChat necesita para no
    // lanzar y dejar el chat cargando.
    const call = dispatch.mock.calls.find(([name]) => name === 'setActiveChat');
    expect(Array.isArray(call[1].data.messages)).toBe(true);
  });

  it('limpia el chat activo al desmontarse para no contaminar la bandeja', async () => {
    const wrapper = mountPanel();
    await flush();
    dispatch.mockClear();

    wrapper.unmount();

    expect(dispatch).toHaveBeenCalledWith('clearSelectedState');
  });

  it('no activa nada cuando el contacto no tiene conversaciones', async () => {
    mountPanel([]);
    await flush();

    expect(dispatch).not.toHaveBeenCalledWith(
      'setActiveChat',
      expect.anything()
    );
  });
});
