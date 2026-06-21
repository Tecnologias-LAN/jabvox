import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import { analyticsPermissionsAPI } from 'dashboard/api/jabvox/analytics';

export const useAnalyticsPermissionsStore = defineStore(
  'analyticsPermissions',
  {
    state: () => ({
      matrix: [],
      roles: [],
      rolePermissions: {},
      auditLogs: [],
      uiFlags: { fetching: false, saving: false },
    }),

    getters: {
      roleList: state => camelcaseKeys(state.roles, { deep: true }),
      userMatrix: state => camelcaseKeys(state.matrix, { deep: true }),
    },

    actions: {
      async fetchRoles() {
        const { data } = await analyticsPermissionsAPI.getRoles();
        this.roles = data;
      },

      async fetchRolePermissions() {
        const { data } = await analyticsPermissionsAPI.getRolePermissions();
        this.rolePermissions = camelcaseKeys(data, { deep: true });
      },

      async updateRolePermissions(roleId, grants) {
        this.uiFlags.saving = true;
        try {
          await analyticsPermissionsAPI.updateRolePermissions(roleId, grants);
        } finally {
          this.uiFlags.saving = false;
        }
      },

      async fetchMatrix() {
        this.uiFlags.fetching = true;
        try {
          const { data } = await analyticsPermissionsAPI.getUserPermissions();
          this.matrix = data;
        } finally {
          this.uiFlags.fetching = false;
        }
      },

      async saveMatrix(payload) {
        this.uiFlags.saving = true;
        try {
          await analyticsPermissionsAPI.bulkUpdateUserPermissions(payload);
          await this.fetchMatrix();
        } finally {
          this.uiFlags.saving = false;
        }
      },

      async fetchAuditLogs(params) {
        const { data } = await analyticsPermissionsAPI.getAuditLogs(params);
        this.auditLogs = data.payload || data;
      },
    },
  }
);
