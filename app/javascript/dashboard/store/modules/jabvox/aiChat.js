import {
  aiChatAPI,
  aiChatModelsAPI,
  aiChatConfigAPI,
  aiChatDocumentsAPI,
} from 'dashboard/api/jabvox/aiChat';

// Los tools persistidos en metadata.tools se guardan con el JSON CRUDO del frame SSE de
// Hermes (toolCallId/tool/label/output/…), distinto a la forma que arma el chat en vivo.
// Esta función los normaliza a la MISMA estructura que espera el template
// ({ id, emoji, tool, label, detail, status }), para que al recargar los chips se vean
// igual que durante el streaming. Debe reflejar la lógica de upsertTool() de AiChat.vue.
const normalizeTool = tool => {
  if (!tool || typeof tool !== 'object') return tool;
  const id = tool.id || tool.toolCallId || tool.tool;
  // Si ya está normalizado (tiene `detail` propio y su `label` es el nombre corto, distinto
  // del frame crudo donde `label` es el comando), lo conservamos: solo garantizamos campos.
  const alreadyNormalized = 'detail' in tool && tool.label === tool.tool;
  if (alreadyNormalized) {
    return {
      id,
      emoji: tool.emoji || '🔧',
      tool: tool.tool || 'tool',
      label: tool.tool || 'tool',
      detail: tool.detail || '',
      status: tool.status || 'completed',
    };
  }
  // Frame CRUDO de Hermes (mismo mapeo que upsertTool): `tool` es el nombre corto (label del
  // chip); el detalle (comando/código/salida) viene en `label`/`detail`/`output`.
  return {
    id,
    emoji: tool.emoji || '🔧',
    tool: tool.tool || 'tool',
    label: tool.tool || 'tool',
    detail: tool.label || tool.detail || tool.output || '',
    status: tool.status || 'completed',
  };
};

const normalizeTools = tools =>
  Array.isArray(tools) ? tools.map(normalizeTool).filter(t => t && t.id) : [];

const state = {
  sessions: [],
  messages: {},
  models: [],
  config: null,
  documents: [],
  myAccess: null,
  uiFlags: {
    isFetchingSessions: false,
    isSending: false,
    isFetchingModels: false,
    isSavingModel: false,
    isFetchingConfig: false,
    isSavingConfig: false,
    isSyncingDocuments: false,
  },
  // Estado de la burbuja flotante (CopilotContainer), separado del store porque el
  // componente se DESMONTA por completo cada vez que se cierra (v-if), y con él
  // cualquier `ref()` local. Vuex sí sobrevive a eso, así que guardar aquí la sesión
  // activa y el progreso del streaming es lo que permite: (1) reabrir la burbuja y
  // seguir viendo la misma conversación en vez de una vacía, y (2) que si hay un
  // streaming en curso al cerrar, al reabrir la UI siga reflejando "está pensando" +
  // las tools en vivo, en vez de perder ese estado visual (el streaming en sí nunca se
  // corta: corre en el módulo del composable, ajeno al ciclo de vida del componente).
  copilotSessionId: null,
  copilotIsStreaming: false,
  copilotActiveTools: [],
  // Estado de streaming de la PÁGINA completa (AiChat.vue), separado del de la
  // burbuja por la misma razón: el componente se desmonta al navegar fuera del
  // módulo. Guardarlo en Vuex permite que al volver a mitad de una respuesta la UI
  // siga mostrando "está pensando" + las tools en vivo (el stream en sí vive en el
  // módulo de AiChat.vue y nunca se corta).
  pageIsStreaming: false,
  pageActiveTools: [],
};

const getters = {
  getSessions: s => s.sessions,
  getMessages: s => sessionId => s.messages[sessionId] || [],
  getModels: s => s.models,
  getConfig: s => s.config,
  getDocuments: s => s.documents,
  getMyAccess: s => s.myAccess,
  getUIFlags: s => s.uiFlags,
  getCopilotSessionId: s => s.copilotSessionId,
  getCopilotIsStreaming: s => s.copilotIsStreaming,
  getCopilotActiveTools: s => s.copilotActiveTools,
  getPageIsStreaming: s => s.pageIsStreaming,
  getPageActiveTools: s => s.pageActiveTools,
};

const mutations = {
  SET_SESSIONS(s, sessions) {
    s.sessions = sessions;
  },
  SET_MESSAGES(s, { sessionId, messages }) {
    // Rehidrata las herramientas ejecutadas por el agente desde metadata.tools (el backend
    // las persiste ahí), para que al reabrir el chat reaparezcan los chips de tools que
    // antes solo vivían en memoria y se perdían al salir.
    const withTools = (messages || []).map(m => {
      const raw = m?.metadata?.tools;
      if (!raw || !raw.length) return m;

      // Normaliza a la forma que espera el template (los persistidos vienen crudos).
      const tools = normalizeTools(raw);
      return tools.length ? { ...m, tools } : m;
    });
    s.messages = { ...s.messages, [sessionId]: withTools };
  },
  ADD_MESSAGE(s, { sessionId, message }) {
    const existing = s.messages[sessionId] || [];
    s.messages = { ...s.messages, [sessionId]: [...existing, message] };
  },
  // Añade texto (delta del stream) al contenido de un mensaje ya presente.
  APPEND_MESSAGE_CONTENT(s, { sessionId, messageId, text }) {
    const existing = s.messages[sessionId] || [];
    s.messages = {
      ...s.messages,
      [sessionId]: existing.map(m =>
        m.id === messageId ? { ...m, content: (m.content || '') + text } : m
      ),
    };
  },
  // Guarda las herramientas usadas por el agente en el mensaje (para mostrarlas al final).
  SET_MESSAGE_TOOLS(s, { sessionId, messageId, tools }) {
    const existing = s.messages[sessionId] || [];
    s.messages = {
      ...s.messages,
      [sessionId]: existing.map(m =>
        m.id === messageId ? { ...m, tools } : m
      ),
    };
  },
  REMOVE_SESSION(s, sessionId) {
    s.sessions = s.sessions.filter(ses => ses.session_id !== sessionId);
    const msgs = { ...s.messages };
    delete msgs[sessionId];
    s.messages = msgs;
  },
  // Re-clava los mensajes de una sesión temporal (pending_<ts>) al session_id REAL que devolvió
  // el backend al abrir el stream. Así, si el usuario sale durante/tras el primer turno, la
  // sesión no se pierde: sus mensajes quedan bajo el UUID real que el historial sí conoce.
  REKEY_SESSION(s, { fromSessionId, toSessionId }) {
    if (!fromSessionId || !toSessionId || fromSessionId === toSessionId) return;
    const existing = s.messages[fromSessionId];
    if (existing === undefined) return;
    const msgs = { ...s.messages };
    // Si ya hay mensajes bajo el id real, se antepone lo temporal para no perder nada.
    msgs[toSessionId] = [...existing, ...(msgs[toSessionId] || [])];
    delete msgs[fromSessionId];
    s.messages = msgs;
  },
  // Actualiza el título de una sesión en la lista (tras renombrar).
  UPDATE_SESSION_TITLE(s, { sessionId, title }) {
    s.sessions = s.sessions.map(ses =>
      ses.session_id === sessionId ? { ...ses, title } : ses
    );
  },
  SET_COPILOT_SESSION_ID(s, sessionId) {
    s.copilotSessionId = sessionId;
  },
  SET_COPILOT_IS_STREAMING(s, value) {
    s.copilotIsStreaming = value;
  },
  SET_COPILOT_ACTIVE_TOOLS(s, tools) {
    s.copilotActiveTools = tools;
  },
  SET_PAGE_IS_STREAMING(s, value) {
    s.pageIsStreaming = value;
  },
  SET_PAGE_ACTIVE_TOOLS(s, tools) {
    s.pageActiveTools = tools;
  },
  SET_MODELS(s, models) {
    s.models = models;
  },
  ADD_MODEL(s, model) {
    s.models = [...s.models, model];
  },
  UPDATE_MODEL(s, updated) {
    s.models = s.models.map(m => (m.id === updated.id ? updated : m));
  },
  REMOVE_MODEL(s, id) {
    s.models = s.models.filter(m => m.id !== id);
  },
  SET_DEFAULT_MODEL(s, id) {
    s.models = s.models.map(m => ({ ...m, is_default_jabvox: m.id === id }));
  },
  SET_CONFIG(s, config) {
    s.config = config;
  },
  SET_DOCUMENTS(s, docs) {
    s.documents = docs;
  },
  UPDATE_DOCUMENT(s, updated) {
    s.documents = s.documents.map(d => (d.id === updated.id ? updated : d));
  },
  REMOVE_DOCUMENT(s, id) {
    s.documents = s.documents.filter(d => d.id !== id);
  },
  SET_MY_ACCESS(s, access) {
    s.myAccess = access;
  },
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
};

const actions = {
  async fetchMyAccess({ commit }) {
    try {
      const { data } = await aiChatAPI.getMyAccess();
      commit('SET_MY_ACCESS', data);
    } catch (e) {
      // Access is best-effort; on failure keep the previous value.
      e?.toString();
    }
  },

  async fetchSessions({ commit }) {
    commit('SET_UI_FLAG', { isFetchingSessions: true });
    try {
      const { data } = await aiChatAPI.getSessions();
      commit('SET_SESSIONS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingSessions: false });
    }
  },

  async fetchMessages({ commit }, sessionId) {
    try {
      const { data } = await aiChatAPI.getMessages(sessionId);
      commit('SET_MESSAGES', { sessionId, messages: data });
    } catch (e) {
      // Messages load opportunistically; ignore fetch failures.
      e?.toString();
    }
  },

  async sendMessage({ commit }, payload) {
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const { data } = await aiChatAPI.sendMessage(payload);
      commit('ADD_MESSAGE', {
        sessionId: data.session_id,
        message: { ...data.message, role: 'assistant' },
      });
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  async deleteSession({ commit }, sessionId) {
    await aiChatAPI.deleteSession(sessionId);
    commit('REMOVE_SESSION', sessionId);
  },

  // Renombra una sesión (compartida por cuenta) y refleja el título en la lista.
  async renameSession({ commit }, { sessionId, title }) {
    const { data } = await aiChatAPI.renameSession(sessionId, title);
    commit('UPDATE_SESSION_TITLE', {
      sessionId,
      title: data?.title ?? title,
    });
    return data;
  },

  async fetchModels({ commit }) {
    commit('SET_UI_FLAG', { isFetchingModels: true });
    try {
      const { data } = await aiChatModelsAPI.getAll();
      commit('SET_MODELS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingModels: false });
    }
  },

  async createModel({ commit }, payload) {
    commit('SET_UI_FLAG', { isSavingModel: true });
    try {
      const { data } = await aiChatModelsAPI.create(payload);
      commit('ADD_MODEL', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSavingModel: false });
    }
  },

  async updateModel({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSavingModel: true });
    try {
      const { data } = await aiChatModelsAPI.update(id, payload);
      commit('UPDATE_MODEL', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSavingModel: false });
    }
  },

  async deleteModel({ commit }, id) {
    await aiChatModelsAPI.destroy(id);
    commit('REMOVE_MODEL', id);
  },

  async setDefaultModel({ commit }, id) {
    await aiChatModelsAPI.setDefault(id);
    commit('SET_DEFAULT_MODEL', id);
  },

  async fetchConfig({ commit }) {
    commit('SET_UI_FLAG', { isFetchingConfig: true });
    try {
      const { data } = await aiChatConfigAPI.get();
      commit('SET_CONFIG', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingConfig: false });
    }
  },

  async updateConfig({ commit }, payload) {
    commit('SET_UI_FLAG', { isSavingConfig: true });
    try {
      const { data } = await aiChatConfigAPI.update(payload);
      commit('SET_CONFIG', data);
    } finally {
      commit('SET_UI_FLAG', { isSavingConfig: false });
    }
  },

  // Lists a folder in the bucket for the picker. Returns { folders, files, limit }.
  // Does not mutate the stored document list — pure listing.
  async fetchBucketObjects(_ctx, { prefix = '', search = '' } = {}) {
    const { data } = await aiChatConfigAPI.bucketObjects({ prefix, search });
    return data;
  },

  // Persists the user's manual selection of bucket file keys as the active set.
  async saveDocuments({ commit }, keys) {
    commit('SET_UI_FLAG', { isSyncingDocuments: true });
    try {
      const { data } = await aiChatConfigAPI.saveDocuments(keys);
      commit('SET_DOCUMENTS', Array.isArray(data) ? data : data.documents);
      return Array.isArray(data) ? { documents: data } : data;
    } finally {
      commit('SET_UI_FLAG', { isSyncingDocuments: false });
    }
  },

  async fetchDocuments({ commit }) {
    try {
      const { data } = await aiChatDocumentsAPI.getAll();
      commit('SET_DOCUMENTS', data);
    } catch (e) {
      // Documents load opportunistically; ignore fetch failures.
      e?.toString();
    }
  },

  async toggleDocument({ commit }, { id, is_enabled_jabvox }) {
    const { data } = await aiChatDocumentsAPI.update(id, { is_enabled_jabvox });
    commit('UPDATE_DOCUMENT', data);
  },
};

export default { namespaced: true, state, getters, mutations, actions };
