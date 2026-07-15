/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/data_export', { accountScoped: true });
const base = client.url;

// Export target = the account's external DB that mirrors its data. Credentials are
// never returned by the API (only has_password); the module only writes.
export const dataExportAPI = {
  getAll: () => axios.get(`${base}/targets`),
  create: target => axios.post(`${base}/targets`, { target }),
  update: (id, target) => axios.patch(`${base}/targets/${id}`, { target }),
  destroy: id => axios.delete(`${base}/targets/${id}`),
  test: target => axios.post(`${base}/targets/test_connection`, { target }),
  testSaved: id => axios.post(`${base}/targets/${id}/test_connection`),
  buildSchema: id => axios.post(`${base}/targets/${id}/build_schema`),
  toggle: (id, enabled) =>
    axios.post(`${base}/targets/${id}/toggle`, { enabled }),
  // Map mode: introspect the customer DB + list the jabvox tables/columns to map from.
  remoteSchema: id => axios.get(`${base}/targets/${id}/remote_schema`),
  // Save mode + field mapping (+ create-missing-columns flag).
  saveMapping: (id, target) =>
    axios.post(`${base}/targets/${id}/mapping`, { target }),
  // Enqueue a manual full backfill.
  syncNow: id => axios.post(`${base}/targets/${id}/sync_now`),
};
