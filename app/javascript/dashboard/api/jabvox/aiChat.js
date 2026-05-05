/* global axios */
import ApiClient from '../ApiClient';

const chatClient = new ApiClient('jabvox/ai_chat_messages', {
  accountScoped: true,
});
const modelsClient = new ApiClient('jabvox/ai_chat_models', {
  accountScoped: true,
});
const configClient = new ApiClient('jabvox/ai_chat_configs', {
  accountScoped: true,
});
const documentsClient = new ApiClient('jabvox/ai_chat_documents', {
  accountScoped: true,
});
const permissionsClient = new ApiClient('jabvox/ai_chat_permissions', {
  accountScoped: true,
});

export const aiChatAPI = {
  getMyAccess: () => axios.get(`${chatClient.url}/my_access`),
  getSessions: () => axios.get(`${chatClient.url}/sessions`),
  getMessages: (sessionId, page = 1) =>
    axios.get(chatClient.url, { params: { session_id: sessionId, page } }),
  sendMessage: payload => axios.post(chatClient.url, payload),
  deleteSession: sessionId => axios.delete(`${chatClient.url}/${sessionId}`),
};

export const aiChatModelsAPI = {
  getAll: () => axios.get(modelsClient.url),
  create: data => axios.post(modelsClient.url, { jabvox_ai_chat_model: data }),
  update: (id, data) =>
    axios.patch(`${modelsClient.url}/${id}`, { jabvox_ai_chat_model: data }),
  destroy: id => axios.delete(`${modelsClient.url}/${id}`),
  setDefault: id => axios.patch(`${modelsClient.url}/${id}/set_default`),
  testConnection: id => axios.post(`${modelsClient.url}/${id}/test_connection`),
};

export const aiChatConfigAPI = {
  get: () => axios.get(configClient.url),
  update: data =>
    axios.patch(configClient.url, { jabvox_ai_chat_config: data }),
  syncDocuments: () => axios.post(`${configClient.url}/sync_documents`),
};

export const aiChatDocumentsAPI = {
  getAll: () => axios.get(documentsClient.url),
  update: (id, data) =>
    axios.patch(`${documentsClient.url}/${id}`, {
      jabvox_ai_chat_document: data,
    }),
  destroy: id => axios.delete(`${documentsClient.url}/${id}`),
};

export const aiChatPermissionsAPI = {
  getAll: () => axios.get(permissionsClient.url),
  update: (userId, data) =>
    axios.patch(`${permissionsClient.url}/${userId}`, { permission: data }),
  bulkUpdate: permissions =>
    axios.patch(`${permissionsClient.url}/bulk_update`, { permissions }),
};
