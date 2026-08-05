/* global axios */
import ApiClient from '../ApiClient';

// Módulo de Tickets (helpdesk): CRUD + ciclo de vida, comentarios, categorías,
// métricas y permisos. accountScoped inyecta /api/v1/accounts/:accountId.
const client = new ApiClient('jabvox/tickets/tickets', { accountScoped: true });
const categoriesClient = new ApiClient('jabvox/tickets/categories', {
  accountScoped: true,
});
const metricsClient = new ApiClient('jabvox/tickets/metrics', {
  accountScoped: true,
});
const permissionsClient = new ApiClient('jabvox/tickets/permissions', {
  accountScoped: true,
});
const notificationPrefsClient = new ApiClient(
  'jabvox/tickets/notification_preferences',
  { accountScoped: true }
);

export default {
  // Tickets
  getAll: (params = {}) => axios.get(client.url, { params }),
  getById: id => axios.get(`${client.url}/${id}`),
  // idempotencyKey protege ante doble-submit/reintentos (el backend deduplica).
  create: (payload, idempotencyKey = null) => {
    const headers = {};
    if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
    if (payload instanceof FormData) {
      headers['Content-Type'] = 'multipart/form-data';
      return axios.post(client.url, payload, { headers });
    }
    return axios.post(client.url, payload, { headers });
  },
  update: (id, payload) => axios.patch(`${client.url}/${id}`, payload),
  remove: id => axios.delete(`${client.url}/${id}`),
  assign: (id, assigneeId) =>
    axios.post(`${client.url}/${id}/assign`, { assignee_id: assigneeId }),
  changeStatus: (id, status) =>
    axios.post(`${client.url}/${id}/change_status`, { status }),
  resolve: (id, resolution, resolutionType) =>
    axios.post(`${client.url}/${id}/resolve`, {
      resolution,
      resolution_type: resolutionType,
    }),
  reopen: id => axios.post(`${client.url}/${id}/reopen`),
  rate: (id, rating, comment) =>
    axios.post(`${client.url}/${id}/rate`, { rating, comment }),
  restore: id => axios.post(`${client.url}/${id}/restore`),
  merge: (id, targetId) =>
    axios.post(`${client.url}/${id}/merge`, { target_id: targetId }),
  bulkAction: (bulkActionType, ids, value = null) =>
    axios.post(`${client.url}/bulk_action`, {
      bulk_action_type: bulkActionType,
      ids,
      value,
    }),

  // Comentarios
  getComments: ticketId => axios.get(`${client.url}/${ticketId}/comments`),
  addComment: (ticketId, body, isPrivate = false) =>
    axios.post(`${client.url}/${ticketId}/comments`, {
      body,
      private: isPrivate,
    }),

  // Categorías
  getCategories: () => axios.get(categoriesClient.url),
  createCategory: payload => axios.post(categoriesClient.url, payload),
  updateCategory: (id, payload) =>
    axios.patch(`${categoriesClient.url}/${id}`, payload),
  removeCategory: id => axios.delete(`${categoriesClient.url}/${id}`),

  // Métricas y permisos
  getMetrics: () => axios.get(metricsClient.url),
  getPermissions: () => axios.get(permissionsClient.url),

  // Preferencias de notificación del usuario
  getNotificationPreferences: () => axios.get(notificationPrefsClient.url),
  updateNotificationPreferences: payload =>
    axios.patch(notificationPrefsClient.url, payload),
};
