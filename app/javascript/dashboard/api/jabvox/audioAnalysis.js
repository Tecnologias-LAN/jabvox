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
  // URL de descarga del PDF de QA de una llamada (se abre en nueva pestaña).
  resultPdfUrl: resultId => `${base}/reports/result_pdf?result_id=${resultId}`,
};

// ── Configuración de QA ─────────────────────────────────────────────────

// Infaltables por tipificación.
export const audioInfaltablesAPI = {
  getAll: typificationId =>
    axios.get(`${base}/infaltables`, {
      params: { typification_id: typificationId },
    }),
  create: infaltable => axios.post(`${base}/infaltables`, { infaltable }),
  update: (id, infaltable) =>
    axios.patch(`${base}/infaltables/${id}`, { infaltable }),
  destroy: id => axios.delete(`${base}/infaltables/${id}`),
  // Reemplaza en bloque la lista de una tipificación.
  bulkReplace: (typificationId, items) =>
    axios.put(`${base}/infaltables/bulk_replace`, {
      typification_id: typificationId,
      items,
    }),
};

// Criterios de Anatomía / Cercanía.
export const audioAnatomyAPI = {
  getAll: () => axios.get(`${base}/anatomy_criteria`),
  create: criterion => axios.post(`${base}/anatomy_criteria`, { criterion }),
  update: (id, criterion) =>
    axios.patch(`${base}/anatomy_criteria/${id}`, { criterion }),
  destroy: id => axios.delete(`${base}/anatomy_criteria/${id}`),
  seedDefaults: () => axios.post(`${base}/anatomy_criteria/seed_defaults`),
};

// Asesores propios del módulo.
export const audioAdvisorsAPI = {
  getAll: () => axios.get(`${base}/advisors`),
  create: advisor => axios.post(`${base}/advisors`, { advisor }),
  update: (id, advisor) => axios.patch(`${base}/advisors/${id}`, { advisor }),
  destroy: id => axios.delete(`${base}/advisors/${id}`),
  importUsers: () => axios.post(`${base}/advisors/import_users`),
};

// Mapeos código→tipificación y código→asesor (se configuran en la visual).
export const audioCodeMappingsAPI = {
  getAll: kind => axios.get(`${base}/code_mappings`, { params: { kind } }),
  create: codeMapping => axios.post(`${base}/code_mappings`, { code_mapping: codeMapping }),
  update: (id, codeMapping) =>
    axios.patch(`${base}/code_mappings/${id}`, { code_mapping: codeMapping }),
  destroy: id => axios.delete(`${base}/code_mappings/${id}`),
};

// Patrones de nombre de archivo.
export const audioFilenamePatternsAPI = {
  getAll: () => axios.get(`${base}/filename_patterns`),
  create: filenamePattern =>
    axios.post(`${base}/filename_patterns`, {
      filename_pattern: filenamePattern,
    }),
  update: (id, filenamePattern) =>
    axios.patch(`${base}/filename_patterns/${id}`, {
      filename_pattern: filenamePattern,
    }),
  destroy: id => axios.delete(`${base}/filename_patterns/${id}`),
  // Prueba un patrón contra un nombre de ejemplo sin guardar.
  test: (pattern, sample, dateFormat) =>
    axios.post(`${base}/filename_patterns/test`, {
      pattern,
      sample,
      date_format: dateFormat,
    }),
};
