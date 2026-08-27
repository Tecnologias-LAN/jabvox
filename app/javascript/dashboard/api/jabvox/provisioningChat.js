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
  // Historial de mensajes [{ id, role, content, metadata, created_at }].
  getMessages: () => axios.get(provisioningChatClient.url),
  // Envía un mensaje del usuario y devuelve la respuesta del assistant.
  sendMessage: content => axios.post(provisioningChatClient.url, { content }),
  // Estado del aprovisionamiento (contextforge, virtual_server, mcp_servers…).
  getStatus: () => axios.get(`${provisioningChatClient.url}/status`),
  // Dispara el aprovisionamiento inicial (crea Hermes + MCPs).
  provision: () => axios.post(`${provisioningChatClient.url}/provision`),
};

export default provisioningChatAPI;
