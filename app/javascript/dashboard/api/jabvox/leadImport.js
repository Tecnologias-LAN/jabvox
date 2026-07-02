/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/lead_import', { accountScoped: true });
const base = client.url;

// External DB connections for importing leads. Credentials are never returned by
// the API (only has_password), so nothing sensitive is ever held in the frontend.
export const leadSourcesAPI = {
  getAll: () => axios.get(`${base}/sources`),
  get: id => axios.get(`${base}/sources/${id}`),
  create: source => axios.post(`${base}/sources`, { source }),
  update: (id, source) => axios.patch(`${base}/sources/${id}`, { source }),
  // purgeLeads=true moves imported leads to the restorable trash; false keeps them.
  destroy: (id, purgeLeads = false) =>
    axios.delete(`${base}/sources/${id}`, {
      params: { purge_leads: purgeLeads },
    }),
  test: source => axios.post(`${base}/sources/test_connection`, { source }),
  testSaved: id => axios.post(`${base}/sources/${id}/test_connection`),
  tables: id => axios.get(`${base}/sources/${id}/tables`),
  columns: (id, table) =>
    axios.get(`${base}/sources/${id}/columns`, { params: { table } }),
  leadFields: () => axios.get(`${base}/sources/lead_fields`),
  createCustomField: payload =>
    axios.post(`${base}/sources/create_custom_field`, payload),
  sync: id => axios.post(`${base}/sources/${id}/sync`),
  syncStatus: id => axios.get(`${base}/sources/${id}/sync_status`),
};
