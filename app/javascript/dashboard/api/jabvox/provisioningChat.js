/* global axios */
import ApiClient from '../ApiClient';

// Cliente del "Chat de Aprovisionamiento": el usuario conversa con el bot
// Hermes para crear los MCPs de su cuenta. Todos los endpoints están
// account-scoped y autenticados por la sesión del dashboard.
const provisioningChatClient = new ApiClient(
  'jabvox/provisioning_chat_messages',
  { accountScoped: true }
);

export const provisioningChatAPI = {
  // Mensajes de UNA conversación [{ id, role, content, metadata, session_id, created_at }].
  // Sin sessionId el backend devuelve la conversación más reciente.
  getMessages: sessionId =>
    axios.get(provisioningChatClient.url, {
      params: sessionId ? { session_id: sessionId } : {},
    }),
  // Conversaciones de la cuenta [{ session_id, last_at, messages_count }].
  getSessions: () => axios.get(`${provisioningChatClient.url}/sessions`),
  // Modelos que ofrece el aprovisionador (para el picker).
  getModelOptions: () =>
    axios.get(`${provisioningChatClient.url}/model_options`),
  // Borra una conversación completa.
  deleteSession: sessionId =>
    axios.delete(`${provisioningChatClient.url}/destroy_session`, {
      params: { session_id: sessionId },
    }),
  // Envía un mensaje del usuario y devuelve la respuesta del assistant (modo sync, legacy).
  sendMessage: content => axios.post(provisioningChatClient.url, { content }),
  // URL del endpoint de streaming (SSE) — el componente hace fetch directo para leer el
  // progreso en vivo (texto + herramientas del aprovisionador), igual que el Chat IA.
  streamUrl: () => `${provisioningChatClient.url}/stream`,
  // --- Control de sesión del agente (API de runs de Hermes) ---
  // Responde una aprobación pendiente. `choice` sale de approval.choices (dinámico).
  approve: (runId, choice, requestId) =>
    axios.post(`${provisioningChatClient.url}/approve`, {
      run_id: runId,
      choice,
      request_id: requestId,
    }),
  // Inyecta guía a un run en curso (/steer).
  steer: (runId, text) =>
    axios.post(`${provisioningChatClient.url}/steer`, { run_id: runId, text }),
  // Interrumpe un run activo.
  stopRun: runId =>
    axios.post(`${provisioningChatClient.url}/stop_run`, { run_id: runId }),
  // Fija el modelo/proveedor de una sesión de Hermes (/model).
  setModel: (hermesSessionId, model, provider) =>
    axios.post(`${provisioningChatClient.url}/set_model`, {
      hermes_session_id: hermesSessionId,
      model,
      provider,
    }),
  // Estado del aprovisionamiento (contextforge, virtual_server, mcp_servers…).
  getStatus: () => axios.get(`${provisioningChatClient.url}/status`),
  // Dispara el aprovisionamiento inicial (crea Hermes + MCPs).
  provision: () => axios.post(`${provisioningChatClient.url}/provision`),
};

export default provisioningChatAPI;
