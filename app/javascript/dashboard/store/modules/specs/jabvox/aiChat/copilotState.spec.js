import aiChat from '../../../jabvox/aiChat';

// Estado de la burbuja flotante (CopilotContainer), guardado en Vuex a propósito: el
// componente se desmonta por completo cada vez que la burbuja se cierra (v-if), así que
// cualquier estado que deba SOBREVIVIR a un cierre/reapertura no puede vivir en un ref()
// local del componente. Estas mutations/getters son la fuente de verdad para: la sesión
// activa, si hay un streaming en curso, y las tools en vivo del turno actual.
const { getters, mutations } = aiChat;

describe('copilot state (bubble persistence)', () => {
  describe('getters', () => {
    it('getCopilotSessionId returns the stored session id', () => {
      const state = { copilotSessionId: 'abc-123' };
      expect(getters.getCopilotSessionId(state)).toBe('abc-123');
    });

    it('getCopilotIsStreaming returns the stored streaming flag', () => {
      const state = { copilotIsStreaming: true };
      expect(getters.getCopilotIsStreaming(state)).toBe(true);
    });

    it('getCopilotActiveTools returns the stored tools array', () => {
      const tools = [{ id: 't1', status: 'running' }];
      const state = { copilotActiveTools: tools };
      expect(getters.getCopilotActiveTools(state)).toBe(tools);
    });
  });

  describe('mutations', () => {
    it('SET_COPILOT_SESSION_ID sets the session id', () => {
      const state = { copilotSessionId: null };
      mutations.SET_COPILOT_SESSION_ID(state, 'session-42');
      expect(state.copilotSessionId).toBe('session-42');
    });

    it('SET_COPILOT_SESSION_ID can clear the session id (new chat)', () => {
      const state = { copilotSessionId: 'session-42' };
      mutations.SET_COPILOT_SESSION_ID(state, null);
      expect(state.copilotSessionId).toBeNull();
    });

    it('SET_COPILOT_IS_STREAMING toggles the streaming flag', () => {
      const state = { copilotIsStreaming: false };
      mutations.SET_COPILOT_IS_STREAMING(state, true);
      expect(state.copilotIsStreaming).toBe(true);

      mutations.SET_COPILOT_IS_STREAMING(state, false);
      expect(state.copilotIsStreaming).toBe(false);
    });

    it('SET_COPILOT_ACTIVE_TOOLS replaces the active tools list', () => {
      const state = { copilotActiveTools: [] };
      const tools = [{ id: 't1', status: 'running' }];
      mutations.SET_COPILOT_ACTIVE_TOOLS(state, tools);
      expect(state.copilotActiveTools).toEqual(tools);
    });
  });

  describe('initial state', () => {
    it('starts with no active session, not streaming, and no active tools', () => {
      const freshState = aiChat.state;
      expect(freshState.copilotSessionId).toBeNull();
      expect(freshState.copilotIsStreaming).toBe(false);
      expect(freshState.copilotActiveTools).toEqual([]);
    });
  });
});
