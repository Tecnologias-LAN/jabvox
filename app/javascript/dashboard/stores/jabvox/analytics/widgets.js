import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import { analyticsDashboardsAPI } from 'dashboard/api/jabvox/analytics';

export const useAnalyticsWidgetsStore = defineStore('analyticsWidgets', {
  state: () => ({
    widgetsByDashboard: {},
    dataByWidget: {},
    uiFlags: { loadingWidget: {} },
  }),

  getters: {
    forDashboard: state => dashboardId =>
      camelcaseKeys(state.widgetsByDashboard[dashboardId] || [], {
        deep: true,
      }),
    dataFor: state => widgetId => state.dataByWidget[widgetId],
  },

  actions: {
    async fetchWidgets(dashboardId) {
      const { data } = await analyticsDashboardsAPI.getWidgets(dashboardId);
      this.widgetsByDashboard[dashboardId] = data;
      return camelcaseKeys(data, { deep: true });
    },

    async addWidget(dashboardId, payload) {
      const { data } = await analyticsDashboardsAPI.createWidget(
        dashboardId,
        payload
      );
      const list = this.widgetsByDashboard[dashboardId] || [];
      this.widgetsByDashboard[dashboardId] = [...list, data];
      return camelcaseKeys(data, { deep: true });
    },

    async updateWidget(dashboardId, widgetId, payload) {
      const { data } = await analyticsDashboardsAPI.updateWidget(
        dashboardId,
        widgetId,
        payload
      );
      const list = this.widgetsByDashboard[dashboardId] || [];
      const idx = list.findIndex(w => w.id === Number(widgetId));
      if (idx !== -1) list.splice(idx, 1, data);
      return camelcaseKeys(data, { deep: true });
    },

    async deleteWidget(dashboardId, widgetId) {
      await analyticsDashboardsAPI.deleteWidget(dashboardId, widgetId);
      const list = this.widgetsByDashboard[dashboardId] || [];
      this.widgetsByDashboard[dashboardId] = list.filter(
        w => w.id !== Number(widgetId)
      );
    },

    async refreshWidget(dashboardId, widgetId, globalFilters = {}) {
      this.uiFlags.loadingWidget[widgetId] = true;
      try {
        const { data } = await analyticsDashboardsAPI.executeWidget(
          dashboardId,
          widgetId,
          globalFilters
        );
        this.dataByWidget[widgetId] = camelcaseKeys(data, { deep: true });
        return this.dataByWidget[widgetId];
      } finally {
        this.uiFlags.loadingWidget[widgetId] = false;
      }
    },
  },
});
