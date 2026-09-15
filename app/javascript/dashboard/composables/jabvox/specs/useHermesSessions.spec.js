import { ref } from 'vue';
import { useHermesSessions } from '../useHermesSessions';
import { hermesConnectionsAPI } from 'dashboard/api/jabvox/aiChat';

vi.mock('dashboard/api/jabvox/aiChat', () => ({
  hermesConnectionsAPI: {
    mine: vi.fn(),
    modelOptions: vi.fn(),
  },
}));

const storeState = { sessions: [] };
const dispatch = vi.fn();

vi.mock('vuex', () => ({
  useStore: () => ({
    dispatch,
    getters: {
      get 'jabvoxAiChat/getSessions'() {
        return storeState.sessions;
      },
    },
  }),
}));

describe('useHermesSessions', () => {
  beforeEach(() => {
    storeState.sessions = [];
    dispatch.mockReset();
    dispatch.mockResolvedValue(undefined);
    hermesConnectionsAPI.mine.mockReset();
    hermesConnectionsAPI.modelOptions.mockReset();
  });

  describe('loadAgents', () => {
    it('selects the first agent by default', async () => {
      hermesConnectionsAPI.mine.mockResolvedValue({
        data: [
          { id: 1, name: 'Ana' },
          { id: 2, name: 'Beto' },
        ],
      });
      const { loadAgents, selectedAgentId, hasAgents } = useHermesSessions();

      await loadAgents();

      expect(selectedAgentId.value).toBe(1);
      expect(hasAgents.value).toBe(true);
    });

    // keepSelection existe para que restaurar una sesión no quede pisado por el primer
    // agente de la lista: la sesión manda sobre el default.
    it('keeps an already selected agent when asked to', async () => {
      hermesConnectionsAPI.mine.mockResolvedValue({
        data: [
          { id: 1, name: 'Ana' },
          { id: 2, name: 'Beto' },
        ],
      });
      const { loadAgents, selectedAgentId } = useHermesSessions();
      selectedAgentId.value = 2;

      await loadAgents({ keepSelection: true });

      expect(selectedAgentId.value).toBe(2);
    });

    it('survives an API failure without agents', async () => {
      hermesConnectionsAPI.mine.mockRejectedValue(new Error('network down'));
      const { loadAgents, hermesAgents, hasAgents } = useHermesSessions();

      await expect(loadAgents()).resolves.toEqual([]);
      expect(hermesAgents.value).toEqual([]);
      expect(hasAgents.value).toBe(false);
    });

    it('handles an empty agent list', async () => {
      hermesConnectionsAPI.mine.mockResolvedValue({ data: [] });
      const { loadAgents, selectedAgentId, hasAgents } = useHermesSessions();

      await loadAgents();

      expect(selectedAgentId.value).toBeNull();
      expect(hasAgents.value).toBe(false);
    });

    it('handles a null payload', async () => {
      hermesConnectionsAPI.mine.mockResolvedValue({ data: null });
      const { loadAgents, hermesAgents } = useHermesSessions();

      await loadAgents();

      expect(hermesAgents.value).toEqual([]);
    });
  });

  describe('selectSession', () => {
    // Regla central: la sesión manda sobre el agente elegido, para que una conversación
    // nunca continúe con un interlocutor distinto al que la inició.
    it('switches to the agent that owns the session', async () => {
      storeState.sessions = [{ session_id: 'a', connection_id: 7 }];
      const sessionId = ref(null);
      const { selectSession, selectedAgentId } = useHermesSessions({
        sessionId,
      });
      selectedAgentId.value = 1;

      await selectSession('a');

      expect(selectedAgentId.value).toBe(7);
      expect(sessionId.value).toBe('a');
      expect(dispatch).toHaveBeenCalledWith('jabvoxAiChat/fetchMessages', 'a');
    });

    it('leaves the agent untouched when the session has no owner', async () => {
      storeState.sessions = [{ session_id: 'a' }];
      const { selectSession, selectedAgentId } = useHermesSessions();
      selectedAgentId.value = 3;

      await selectSession('a');

      expect(selectedAgentId.value).toBe(3);
    });

    it('still fetches messages for a session it does not know yet', async () => {
      storeState.sessions = [];
      const { selectSession } = useHermesSessions();

      await expect(selectSession('ghost')).resolves.toBeUndefined();
      expect(dispatch).toHaveBeenCalledWith(
        'jabvoxAiChat/fetchMessages',
        'ghost'
      );
    });
  });

  describe('restoreLastSession', () => {
    it('opens the most recent session', async () => {
      const sessionId = ref(null);
      dispatch.mockImplementation(async action => {
        if (action === 'jabvoxAiChat/fetchSessions') {
          storeState.sessions = [
            { session_id: 'newest', connection_id: 4 },
            { session_id: 'older', connection_id: 5 },
          ];
        }
      });
      const { restoreLastSession, selectedAgentId } = useHermesSessions({
        sessionId,
      });

      const restored = await restoreLastSession();

      expect(restored.session_id).toBe('newest');
      expect(sessionId.value).toBe('newest');
      expect(selectedAgentId.value).toBe(4);
    });

    it('returns null when there are no sessions', async () => {
      const { restoreLastSession } = useHermesSessions();
      await expect(restoreLastSession()).resolves.toBeNull();
    });
  });

  describe('sessionBelongsToOtherAgent', () => {
    beforeEach(() => {
      storeState.sessions = [
        { session_id: 'owned', connection_id: 7 },
        { session_id: 'orphan' },
      ];
    });

    it('detects a session owned by a different agent', () => {
      const { sessionBelongsToOtherAgent } = useHermesSessions();
      expect(sessionBelongsToOtherAgent('owned', 9)).toBe(true);
    });

    it('accepts the session of the same agent', () => {
      const { sessionBelongsToOtherAgent } = useHermesSessions();
      expect(sessionBelongsToOtherAgent('owned', 7)).toBe(false);
    });

    it('treats a session without owner as compatible', () => {
      const { sessionBelongsToOtherAgent } = useHermesSessions();
      expect(sessionBelongsToOtherAgent('orphan', 9)).toBe(false);
    });

    it('treats an unknown session as compatible', () => {
      const { sessionBelongsToOtherAgent } = useHermesSessions();
      expect(sessionBelongsToOtherAgent('missing', 9)).toBe(false);
    });
  });

  describe('loadModelOptions', () => {
    it('flattens authenticated providers and marks the current model', async () => {
      hermesConnectionsAPI.modelOptions.mockResolvedValue({
        data: {
          model: 'glm-5',
          providers: [
            { slug: 'zai', models: ['glm-5', 'glm-4'], is_current: true },
            { slug: 'openai', models: ['gpt-4'], authenticated: false },
          ],
        },
      });
      const { loadModelOptions, modelOptions, selectedModelKey } =
        useHermesSessions();

      await loadModelOptions(1);

      expect(modelOptions.value.map(o => o.value)).toEqual([
        'zai::glm-5',
        'zai::glm-4',
      ]);
      expect(selectedModelKey.value).toBe('zai::glm-5');
    });

    it('clears the options when no connection is given', async () => {
      const { loadModelOptions, modelOptions } = useHermesSessions();
      await loadModelOptions(null);
      expect(modelOptions.value).toEqual([]);
      expect(hermesConnectionsAPI.modelOptions).not.toHaveBeenCalled();
    });

    it('falls back to no options when the API fails', async () => {
      hermesConnectionsAPI.modelOptions.mockRejectedValue(new Error('boom'));
      const { loadModelOptions, modelOptions } = useHermesSessions();

      await loadModelOptions(1);

      expect(modelOptions.value).toEqual([]);
    });

    it('handles a malformed payload', async () => {
      hermesConnectionsAPI.modelOptions.mockResolvedValue({ data: null });
      const { loadModelOptions, modelOptions, selectedModelKey } =
        useHermesSessions();

      await loadModelOptions(1);

      expect(modelOptions.value).toEqual([]);
      expect(selectedModelKey.value).toBe('');
    });

    // Jabvox no valida la respuesta de Hermes (la reenvía cruda), así que el parser tolera
    // las variantes observadas en vez de asumir una sola forma.
    it('accepts a bare array of providers', async () => {
      hermesConnectionsAPI.modelOptions.mockResolvedValue({
        data: [{ slug: 'zai', models: ['glm-5'] }],
      });
      const { loadModelOptions, modelOptions } = useHermesSessions();

      await loadModelOptions(1);

      expect(modelOptions.value).toEqual([
        {
          value: 'zai::glm-5',
          label: 'glm-5',
          provider: 'zai',
          model: 'glm-5',
        },
      ]);
    });

    it('accepts models given as objects', async () => {
      hermesConnectionsAPI.modelOptions.mockResolvedValue({
        data: { providers: [{ name: 'zai', models: [{ id: 'glm-5' }] }] },
      });
      const { loadModelOptions, modelOptions } = useHermesSessions();

      await loadModelOptions(1);

      expect(modelOptions.value[0].value).toBe('zai::glm-5');
    });

    it('accepts options[] as an alias of models[]', async () => {
      hermesConnectionsAPI.modelOptions.mockResolvedValue({
        data: { providers: [{ provider: 'zai', options: ['glm-5'] }] },
      });
      const { loadModelOptions, modelOptions } = useHermesSessions();

      await loadModelOptions(1);

      expect(modelOptions.value[0].value).toBe('zai::glm-5');
    });

    it('skips entries without a usable provider or model name', async () => {
      hermesConnectionsAPI.modelOptions.mockResolvedValue({
        data: {
          providers: [
            { models: ['huérfano'] },
            { slug: 'zai', models: [{}, '', 'glm-5'] },
          ],
        },
      });
      const { loadModelOptions, modelOptions } = useHermesSessions();

      await loadModelOptions(1);

      expect(modelOptions.value.map(o => o.value)).toEqual(['zai::glm-5']);
    });

    it('leaves the default selected when no provider is current', async () => {
      hermesConnectionsAPI.modelOptions.mockResolvedValue({
        data: { model: 'glm-5', providers: [{ slug: 'zai', models: ['x'] }] },
      });
      const { loadModelOptions, selectedModelKey } = useHermesSessions();

      await loadModelOptions(1);

      expect(selectedModelKey.value).toBe('');
    });
  });

  describe('selectedModelOverride', () => {
    it('is empty while the default model is selected', () => {
      const { selectedModelOverride } = useHermesSessions();
      expect(selectedModelOverride.value).toEqual({});
    });

    it('carries model and provider once one is picked', async () => {
      hermesConnectionsAPI.modelOptions.mockResolvedValue({
        data: {
          model: 'glm-5',
          providers: [{ slug: 'zai', models: ['glm-5'], is_current: true }],
        },
      });
      const { loadModelOptions, selectedModelOverride } = useHermesSessions();

      await loadModelOptions(1);

      expect(selectedModelOverride.value).toEqual({
        llm_model: 'glm-5',
        llm_provider: 'zai',
      });
    });
  });

  describe('under load', () => {
    it('keeps the selection consistent across many sessions', async () => {
      storeState.sessions = Array.from({ length: 500 }, (_, i) => ({
        session_id: `s-${i}`,
        connection_id: (i % 7) + 1,
      }));
      const sessionId = ref(null);
      const { selectSession, selectedAgentId } = useHermesSessions({
        sessionId,
      });

      // Saltar entre conversaciones de agentes distintos debe dejar SIEMPRE el agente
      // dueño de la última sesión abierta, sin arrastrar el de la anterior.
      for (let i = 0; i < 500; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await selectSession(`s-${i}`);
        expect(selectedAgentId.value).toBe((i % 7) + 1);
      }
      expect(sessionId.value).toBe('s-499');
    });

    it('survives concurrent agent loads without losing the list', async () => {
      hermesConnectionsAPI.mine.mockResolvedValue({
        data: [{ id: 1, name: 'Ana' }],
      });
      const { loadAgents, hermesAgents } = useHermesSessions();

      await Promise.all(Array.from({ length: 25 }, () => loadAgents()));

      expect(hermesAgents.value).toHaveLength(1);
    });
  });
});
