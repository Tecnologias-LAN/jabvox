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
  // Export groups (modules) available for this account, for the config checklist.
  availableGroups: () => axios.get(`${base}/targets/available_groups`),
  // Enqueue a manual full backfill.
  syncNow: id => axios.post(`${base}/targets/${id}/sync_now`),
  // Sync history: counts + paginated records, optionally filtered by status.
  history: (id, { status, page } = {}) =>
    axios.get(`${base}/targets/${id}/history`, { params: { status, page } }),
};
