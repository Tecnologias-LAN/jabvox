/* global axios */
import ApiClient from '../../ApiClient';

// Toda la API de flujos cuelga del espacio de cuenta: el account_id lo resuelve
// ApiClient desde la ruta, y la sesión del dashboard viaja en las cookies.
const client = new ApiClient('jabvox/flows', { accountScoped: true });
const base = () => client.url;

export const flowsAPI = {
  list: params => axios.get(base(), { params }),
  get: id => axios.get(`${base()}/${id}`),
  create: data => axios.post(base(), data),
  update: (id, data) => axios.patch(`${base()}/${id}`, data),
  delete: id => axios.delete(`${base()}/${id}`),
  duplicate: id => axios.post(`${base()}/${id}/duplicate`),

  // Sin `strict` el backend valida en modo permisivo, que es lo que necesita el
  // autoguardado: acepta trabajo a medias y solo rechaza lo estructural.
  saveVersion: (id, graph, strict = false) =>
    axios.put(`${base()}/${id}/versions`, {
      nodes: graph.nodes,
      edges: graph.edges,
      // Notas adhesivas: viajan con el grafo, el motor no las mira.
      notes: graph.notes || [],
      ...(strict ? { strict: true } : {}),
    }),
  validate: (id, graph) =>
    axios.post(
      `${base()}/${id}/validate`,
      graph ? { nodes: graph.nodes, edges: graph.edges } : {}
    ),
  listVersions: id => axios.get(`${base()}/${id}/versions`),
  getVersion: (id, version) => axios.get(`${base()}/${id}/versions/${version}`),
  restoreVersion: (id, version) =>
    axios.post(`${base()}/${id}/versions/${version}/restore`),

  run: (id, payload = {}) => axios.post(`${base()}/${id}/run`, { payload }),
  runNode: (id, nodeId, payload = {}, options = {}) =>
    axios.post(`${base()}/${id}/run_node`, {
      nodeId,
      payload,
      useLastRunContext: options.useLastRunContext !== false,
      ...(options.priorOutputs ? { priorOutputs: options.priorOutputs } : {}),
    }),
  runFrom: (id, nodeId, payload = {}) =>
    axios.post(`${base()}/${id}/run_from`, { nodeId, payload }),
  listRuns: (id, limit = 10) =>
    axios.get(`${base()}/${id}/runs`, { params: { limit } }),

  // Tope de flujos de la cuenta: { used, limit, remaining, unlimited }.
  quota: () => axios.get(`${base()}/quota`),
};

export const foldersAPI = {
  list: () => axios.get(`${base()}/folders`),
  create: name => axios.post(`${base()}/folders`, { name }),
  update: (id, name) => axios.patch(`${base()}/folders/${id}`, { name }),
  delete: id => axios.delete(`${base()}/folders/${id}`),
};

export const variablesAPI = {
  list: () => axios.get(`${base()}/variables`),
  create: data => axios.post(`${base()}/variables`, data),
  update: (id, data) => axios.patch(`${base()}/variables/${id}`, data),
  delete: id => axios.delete(`${base()}/variables/${id}`),
};

export const runsAPI = {
  list: (params = {}) => axios.get(`${base()}/runs`, { params }),
  stats: days => axios.get(`${base()}/runs/stats`, { params: { days } }),
  get: runId => axios.get(`${base()}/runs/${runId}`),
  resume: (runId, payload = {}) =>
    axios.post(`${base()}/runs/${runId}/resume`, { payload }),
};

export const nodesAPI = {
  catalog: () => axios.get(`${base()}/nodes`),
  // `params` lleva las dependencias declaradas por `dependsOn` en el catálogo
  // (funnelId, boardId, inboxId).
  options: (kind, params) => axios.get(`${base()}/options/${kind}`, { params }),
};
