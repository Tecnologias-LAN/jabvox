/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/whatsapp_templates', {
  accountScoped: true,
});
const base = client.url;

export const wtInboxesAPI = {
  getAll: () => axios.get(`${base}/inboxes`),
  sync: inboxId => axios.post(`${base}/inboxes/${inboxId}/sync`),
  // Sync every WhatsApp Cloud inbox with Meta (no inbox needs to be selected).
  syncAll: () => axios.post(`${base}/sync_all`),
  // Background sync, triggered when the module opens.
  syncAllAsync: () => axios.post(`${base}/sync_all_async`),
  metrics: inboxId =>
    axios.get(`${base}/metrics`, {
      params: inboxId ? { inbox_id: inboxId } : {},
    }),
};

export const wtTemplatesAPI = {
  getAll: params => axios.get(`${base}/templates`, { params }),
  get: id => axios.get(`${base}/templates/${id}`),
  create: data => axios.post(`${base}/templates`, data),
  // Sube el media del header a Meta (Resumable Upload) y devuelve { handle: 'h:...' }.
  // Se llama al elegir el archivo, antes de crear la plantilla.
  uploadMedia: ({ inboxId, file }) => {
    const formData = new FormData();
    formData.append('inbox_id', inboxId);
    formData.append('file', file);
    return axios.post(`${base}/templates/upload_media`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
  update: (id, data) => axios.patch(`${base}/templates/${id}`, data),
  duplicate: (id, newName) =>
    axios.post(`${base}/templates/${id}/duplicate`, { new_name: newName }),
  sync: id => axios.post(`${base}/templates/${id}/sync`),
  history: id => axios.get(`${base}/templates/${id}/history`),
  versions: id => axios.get(`${base}/templates/${id}/versions`),
  restoreVersion: (id, versionId) =>
    axios.post(`${base}/templates/${id}/restore_version`, {
      version_id: versionId,
    }),
};
