/* global axios */
import ApiClient from '../../ApiClient';

// Cross-source reports: CRUD + execution. A cross report joins data pulled from
// several data sources (e.g. Wimpos' databases on different servers) by a mapped
// common field. Sources/joins are sent alongside the report on create/update.
class JabvoxAnalyticsCrossReportsAPI extends ApiClient {
  constructor() {
    super('jabvox/analytics/cross_reports', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  // payload: { name_jabvox, description_jabvox, row_limit_jabvox, sources: [...], joins: [...] }
  create(payload) {
    return axios.post(this.url, payload);
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, payload);
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // Runs the cross-source join and returns { columns, rows, row_count, truncated }.
  execute(id) {
    return axios.post(`${this.url}/${id}/execute`);
  }
}

export default new JabvoxAnalyticsCrossReportsAPI();
