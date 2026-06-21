import axios from 'axios';
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/whatsapp_templates', { accountScoped: true });
const base = client.url;

export const wtInboxesAPI = {
  getAll: () => axios.get(`${base}/inboxes`),
  sync: inboxId => axios.post(`${base}/inboxes/${inboxId}/sync`),
  metrics: inboxId => axios.get(`${base}/metrics`, { params: inboxId ? { inbox_id: inboxId } : {} }),
};

export const wtTemplatesAPI = {
  getAll: params => axios.get(`${base}/templates`, { params }),
  get: id => axios.get(`${base}/templates/${id}`),
  create: data => axios.post(`${base}/templates`, data),
  update: (id, data) => axios.patch(`${base}/templates/${id}`, data),
  destroy: id => axios.delete(`${base}/templates/${id}`),
  duplicate: (id, newName) => axios.post(`${base}/templates/${id}/duplicate`, { new_name: newName }),
  sync: id => axios.post(`${base}/templates/${id}/sync`),
  history: id => axios.get(`${base}/templates/${id}/history`),
  versions: id => axios.get(`${base}/templates/${id}/versions`),
  restoreVersion: (id, versionId) => axios.post(`${base}/templates/${id}/restore_version`, { version_id: versionId }),
};

export const wtExportAPI = {
  exportJson: inboxId => axios.get(`${base}/export.json`, { params: inboxId ? { inbox_id: inboxId } : {}, responseType: 'blob' }),
  exportCsv: inboxId => axios.get(`${base}/export.csv`, { params: inboxId ? { inbox_id: inboxId } : {}, responseType: 'blob' }),
};

export const wtImportAPI = {
  importJson: (inboxId, templates) => axios.post(`${base}/import`, { inbox_id: inboxId, templates }),
};

export const wtPermissionsAPI = {
  getAll: () => axios.get(`${base}/permissions`),
  bulk: userIds => axios.patch(`${base}/permissions/bulk`, { user_ids: userIds }),
};
