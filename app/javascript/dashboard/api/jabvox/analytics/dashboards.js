/* global axios */
import ApiClient from '../../ApiClient';

class JabvoxAnalyticsDashboardsAPI extends ApiClient {
  constructor() {
    super('jabvox/analytics/dashboards', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  saveLayout(id, layout) {
    return axios.put(`${this.url}/${id}/layout`, { layout });
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  getWidgets(dashboardId) {
    return axios.get(`${this.url}/${dashboardId}/widgets`);
  }

  createWidget(dashboardId, data) {
    return axios.post(`${this.url}/${dashboardId}/widgets`, { widget: data });
  }

  updateWidget(dashboardId, widgetId, data) {
    return axios.patch(`${this.url}/${dashboardId}/widgets/${widgetId}`, {
      widget: data,
    });
  }

  deleteWidget(dashboardId, widgetId) {
    return axios.delete(`${this.url}/${dashboardId}/widgets/${widgetId}`);
  }

  executeWidget(dashboardId, widgetId, globalFilters = {}) {
    return axios.post(
      `${this.url}/${dashboardId}/widgets/${widgetId}/execute`,
      {
        global_filters: globalFilters,
      }
    );
  }

  getShares(dashboardId) {
    return axios.get(`${this.url}/${dashboardId}/shares`);
  }

  createShare(dashboardId, data) {
    return axios.post(`${this.url}/${dashboardId}/shares`, { share: data });
  }

  deleteShare(dashboardId, shareId) {
    return axios.delete(`${this.url}/${dashboardId}/shares/${shareId}`);
  }
}

export default new JabvoxAnalyticsDashboardsAPI();
