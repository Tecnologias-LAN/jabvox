import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import { analyticsPermissionsAPI } from 'dashboard/api/jabvox/analytics';

// The current user's effective Analytics capabilities, used to gate UI.
export const useAnalyticsCapabilitiesStore = defineStore(
  'analyticsCapabilities',
  {
    state: () => ({
      isAdmin: false,
      capabilities: {},
      loaded: false,
    }),

    getters: {
      can: state => key => state.isAdmin || Boolean(state.capabilities[key]),
      canAccess() {
        return this.can('access');
      },
      canCreate() {
        return this.can('create');
      },
      canManageDataSources() {
        return this.can('manage_data_sources');
      },
      canUseCustomSql() {
        return this.can('use_custom_sql');
      },
    },

    actions: {
      async fetch() {
        const { data } = await analyticsPermissionsAPI.myCapabilities();
        const camel = camelcaseKeys(data, { deep: true });
        this.isAdmin = camel.isAdmin;
        this.capabilities = data.capabilities || {};
        this.loaded = true;
      },
    },
  }
);
