import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { hermesConnectionsAPI } from 'dashboard/api/jabvox/aiChat';

// Sesiones y agentes Hermes de la cuenta. Vive en un composable porque lo usan las dos
// superficies del Chat IA —la página completa y la burbuja flotante— y ambas deben ver
// exactamente las mismas conversaciones y los mismos agentes: si la página lista 4
// sesiones, la burbuja lista esas mismas 4.
//
// Regla central del modelo: cada sesión pertenece a UN agente. Al abrir una sesión se
// selecciona su agente, de modo que una conversación siempre continúa con el mismo
// interlocutor y nunca se responde con otro.

export function useHermesSessions({ sessionId } = {}) {
  const store = useStore();

  const hermesAgents = ref([]);
  const selectedAgentId = ref(null);
  // Picker de modelo LLM del agente (equivale a "/model"). '' = default del agente.
  const modelOptions = ref([]);
  const selectedModelKey = ref('');

  const sessions = computed(() => store.getters['jabvoxAiChat/getSessions']);
  const hasAgents = computed(() => hermesAgents.value.length > 0);

  const agentOptions = computed(() =>
    hermesAgents.value.map(a => ({ value: a.id, label: a.name }))
  );

  // Nombre del agente activo, para mostrarlo en cabeceras compactas como la de la burbuja.
  const selectedAgentName = computed(
    () =>
      hermesAgents.value.find(a => a.id === selectedAgentId.value)?.name || ''
  );

  // El modelo/proveedor elegidos, o {} si se usa el default del agente en Hermes.
  const selectedModelOverride = computed(() => {
    const opt = modelOptions.value.find(
      o => o.value === selectedModelKey.value
    );
    return opt ? { llm_model: opt.model, llm_provider: opt.provider } : {};
  });

  // Jabvox reenvía la respuesta de Hermes a model/options tal cual, sin validarla, así que
  // su forma no está garantizada por ningún contrato de este lado. Toleramos las variantes
  // observadas —providers[] o array raíz; models[] u options[]; slug/name/provider; modelos
  // como string o como objeto {id|name|slug}— igual que hace HermesModelsViewer.
  const providerSlug = p => p?.slug || p?.name || p?.provider || '';
  const modelName = m =>
    typeof m === 'string' ? m : m?.id || m?.name || m?.slug || '';

  const providerList = data => {
    if (Array.isArray(data?.providers)) return data.providers;
    if (Array.isArray(data)) return data;
    return [];
  };

  // Modelos que ofrece el agente elegido, aplanados a {value,label,provider,model} y con el
  // modelo activo preseleccionado. Silencioso si falla: sin opciones el chat sigue
  // funcionando con el default del agente.
  async function loadModelOptions(connectionId) {
    modelOptions.value = [];
    selectedModelKey.value = '';
    if (!connectionId) return;
    try {
      const { data } = await hermesConnectionsAPI.modelOptions(connectionId);
      const providers = providerList(data);
      const opts = [];
      let current = '';
      providers.forEach(p => {
        if (p?.authenticated === false) return;
        const slug = providerSlug(p);
        if (!slug) return;
        (p.models || p.options || []).forEach(m => {
          const name = modelName(m);
          if (!name) return;
          const value = `${slug}::${name}`;
          opts.push({ value, label: name, provider: slug, model: name });
          if (p.is_current && data?.model === name) current = value;
        });
      });
      modelOptions.value = opts;
      selectedModelKey.value = current;
    } catch {
      modelOptions.value = [];
    }
  }

  async function loadAgents({ keepSelection = false } = {}) {
    try {
      const { data } = await hermesConnectionsAPI.mine();
      hermesAgents.value = data || [];
      // keepSelection respeta el agente que ya venía de una sesión restaurada, para no
      // pisarlo con el primero de la lista.
      if (!keepSelection || !selectedAgentId.value) {
        selectedAgentId.value = hermesAgents.value[0]?.id || null;
      }
      return hermesAgents.value;
    } catch {
      hermesAgents.value = [];
      return [];
    }
  }

  // Abre una sesión: fija su agente y carga sus mensajes.
  async function selectSession(id) {
    if (sessionId) sessionId.value = id;
    const session = sessions.value.find(s => s.session_id === id);
    if (session?.connection_id) selectedAgentId.value = session.connection_id;
    await store.dispatch('jabvoxAiChat/fetchMessages', id);
    return session;
  }

  async function fetchSessions() {
    await store.dispatch('jabvoxAiChat/fetchSessions');
    return sessions.value;
  }

  // Recupera la última conversación del backend. La usa la burbuja al abrirse para no
  // arrancar siempre en blanco cuando ya existe una conversación en curso.
  async function restoreLastSession() {
    await fetchSessions();
    const [lastSession] = sessions.value;
    if (!lastSession) return null;
    await selectSession(lastSession.session_id);
    return lastSession;
  }

  // ¿La sesión indicada pertenece a un agente distinto del elegido? Una sesión solo se
  // ejecuta con su propio agente, así que quien cambie de agente a media conversación debe
  // abrir una nueva en lugar de responder con el interlocutor equivocado.
  function sessionBelongsToOtherAgent(id, agentId) {
    const session = sessions.value.find(s => s.session_id === id);
    return !!session?.connection_id && session.connection_id !== agentId;
  }

  return {
    hermesAgents,
    selectedAgentId,
    selectedAgentName,
    sessions,
    hasAgents,
    agentOptions,
    modelOptions,
    selectedModelKey,
    selectedModelOverride,
    loadAgents,
    loadModelOptions,
    selectSession,
    fetchSessions,
    restoreLastSession,
    sessionBelongsToOtherAgent,
  };
}
