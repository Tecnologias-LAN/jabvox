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
const storagesClient = new ApiClient('jabvox/ai_chat_storages', {
  accountScoped: true,
});
// Cron jobs de Hermes: agenda de tareas del asistente por cuenta.
const hermesCronClient = new ApiClient('jabvox/ai_chat_hermes_cron_jobs', {
  accountScoped: true,
});
// Handoff de Hermes (recurso singular): conectar/sincronizar un Hermes existente.
const hermesClient = new ApiClient('jabvox/ai_chat_hermes', {
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
  // Lists a bucket folder (folders + files) so the user can navigate and pick.
  bucketObjects: ({ prefix = '', search = '' } = {}) =>
    axios.get(`${configClient.url}/bucket_objects`, {
      params: { prefix, search },
    }),
  // Persists the manually selected file keys as the active document set.
  saveDocuments: keys =>
    axios.post(`${configClient.url}/save_documents`, { keys }),
};

export const aiChatDocumentsAPI = {
  getAll: () => axios.get(documentsClient.url),
  update: (id, data) =>
    axios.patch(`${documentsClient.url}/${id}`, {
      jabvox_ai_chat_document: data,
    }),
  destroy: id => axios.delete(`${documentsClient.url}/${id}`),
};

// Cron jobs de Hermes: listar, crear, alternar (enabled) y eliminar.
// Endpoints accountScoped, auth por sesión. El GET puede devolver 422
// ({error}) cuando la cuenta aún no está aprovisionada.
export const aiChatHermesCronAPI = {
  getCronJobs: () => axios.get(hermesCronClient.url),
  createCronJob: ({ name, schedule, prompt, enabled }) =>
    axios.post(hermesCronClient.url, { name, schedule, prompt, enabled }),
  toggleCronJob: (id, enabled) =>
    axios.patch(`${hermesCronClient.url}/${id}/toggle`, { enabled }),
  deleteCronJob: id => axios.delete(`${hermesCronClient.url}/${id}`),
};

// Handoff de Hermes: conectar un Hermes ya existente a la cuenta y sincronizar
// modelos. Recurso singular; connect/sync_models son acciones custom. El GET y
// los POST pueden devolver 422 ({error}) cuando la conexión falla o falta.
export const aiChatHermesAPI = {
  getStatus: () => axios.get(hermesClient.url),
  connect: payload => axios.post(`${hermesClient.url}/connect`, payload),
  syncModels: () => axios.post(`${hermesClient.url}/sync_models`),
};

// Shared storage buckets (JabvoxAudioStorage) managed from AI Chat, gated by
// AI Chat's own permission so Audio Analysis need not be enabled.
export const aiChatStoragesAPI = {
  getAll: () => axios.get(storagesClient.url),
  create: storage => axios.post(storagesClient.url, { storage }),
  update: (id, storage) =>
    axios.patch(`${storagesClient.url}/${id}`, { storage }),
  destroy: id => axios.delete(`${storagesClient.url}/${id}`),
  test: storage => axios.post(`${storagesClient.url}/test`, { storage }),
};
