/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/audio_analysis', { accountScoped: true });
const base = client.url;

export const audioStoragesAPI = {
  getAll: () => axios.get(`${base}/storages`),
  create: storage => axios.post(`${base}/storages`, { storage }),
  update: (id, storage) => axios.patch(`${base}/storages/${id}`, { storage }),
  destroy: id => axios.delete(`${base}/storages/${id}`),
  test: storage => axios.post(`${base}/storages/test`, { storage }),
  objects: (id, params) =>
    axios.get(`${base}/storages/${id}/objects`, { params }),
  // Bulk-assign typification/agent to files without analyzing them.
  assign: (id, payload) => axios.post(`${base}/storages/${id}/assign`, payload),
  // Short-lived presigned URL to play a file in the browser.
  playback: (id, fileKey) =>
    axios.get(`${base}/storages/${id}/playback`, {
      params: { file_key: fileKey },
    }),
};

export const audioPipelinesAPI = {
  getAll: () => axios.get(`${base}/pipelines`),
  create: pipeline => axios.post(`${base}/pipelines`, { pipeline }),
  update: (id, pipeline) =>
    axios.patch(`${base}/pipelines/${id}`, { pipeline }),
  destroy: id => axios.delete(`${base}/pipelines/${id}`),
};

export const audioJobsAPI = {
  getAll: () => axios.get(`${base}/jobs`),
  get: id => axios.get(`${base}/jobs/${id}`),
  results: id => axios.get(`${base}/jobs/${id}/results`),
  create: payload => axios.post(`${base}/jobs`, payload),
};

export const audioReportsAPI = {
  myAccess: () => axios.get(`${base}/access/my`),
  daily: params => axios.get(`${base}/reports/daily`, { params }),
  filterOptions: () => axios.get(`${base}/reports/filter_options`),
};

export const audioAccessAPI = {
  users: () => axios.get(`${base}/access/users`),
  updateUser: payload => axios.post(`${base}/access/users`, payload),
};
