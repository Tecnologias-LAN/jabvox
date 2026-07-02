import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import {
  analyticsDashboardsAPI,
  analyticsFoldersAPI,
} from 'dashboard/api/jabvox/analytics';

export const useAnalyticsDashboardsStore = defineStore('analyticsDashboards', {
  state: () => ({
    dashboards: [],
    folders: [],
    currentDashboard: null,
    globalFilters: { dateFrom: null, dateTo: null, dynamic: {} },
    editMode: false,
    uiFlags: { fetchingList: false, fetchingItem: false, saving: false },
  }),

  getters: {
    list: state => camelcaseKeys(state.dashboards, { deep: true }),
    folderTree: state => camelcaseKeys(state.folders, { deep: true }),
  },

  actions: {
    async fetchFolders() {
      const { data } = await analyticsFoldersAPI.get();
      this.folders = data;
    },

    async createFolder(payload) {
      const { data } = await analyticsFoldersAPI.create({ folder: payload });
      this.folders.push(data);
      return camelcaseKeys(data, { deep: true });
    },

    async updateFolder(id, payload) {
      const { data } = await analyticsFoldersAPI.update(id, {
        folder: payload,
      });
      const idx = this.folders.findIndex(f => f.id === Number(id));
      if (idx !== -1) this.folders.splice(idx, 1, data);
      return camelcaseKeys(data, { deep: true });
    },

    async destroyFolder(id) {
      await analyticsFoldersAPI.delete(id);
      this.folders = this.folders.filter(f => f.id !== Number(id));
    },

    async fetchDashboards() {
      this.uiFlags.fetchingList = true;
      try {
        const { data } = await analyticsDashboardsAPI.getAll();
        this.dashboards = data;
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },

    // Catalog of built-in internal reports the user can pick from.
    async fetchInternalReports() {
      const { data } = await analyticsDashboardsAPI.internalReports();
      return data;
    },

    // Create dashboards for the selected report keys, then reload.
    async createInternalReports(keys) {
      await analyticsDashboardsAPI.createInternalReports(keys);
      await this.fetchDashboards();
    },

    async getDashboard(id) {
      this.uiFlags.fetchingItem = true;
      try {
        const { data } = await analyticsDashboardsAPI.show(id);
        this.currentDashboard = camelcaseKeys(data, { deep: true });
        return this.currentDashboard;
      } finally {
        this.uiFlags.fetchingItem = false;
      }
    },

    async create(payload) {
      const { data } = await analyticsDashboardsAPI.create({
        dashboard: payload,
      });
      this.dashboards.push(data);
      return camelcaseKeys(data, { deep: true });
    },

    async update(id, payload) {
      const { data } = await analyticsDashboardsAPI.update(id, {
        dashboard: payload,
      });
      const idx = this.dashboards.findIndex(d => d.id === Number(id));
      if (idx !== -1) this.dashboards.splice(idx, 1, data);
      return camelcaseKeys(data, { deep: true });
    },

    async destroy(id) {
      await analyticsDashboardsAPI.delete(id);
      this.dashboards = this.dashboards.filter(d => d.id !== Number(id));
    },

    async saveLayout(id, layout) {
      this.uiFlags.saving = true;
      try {
        await analyticsDashboardsAPI.saveLayout(id, layout);
      } finally {
        this.uiFlags.saving = false;
      }
    },

    setGlobalFilters(filters) {
      this.globalFilters = { ...this.globalFilters, ...filters };
    },

    setEditMode(value) {
      this.editMode = value;
    },
  },
});
