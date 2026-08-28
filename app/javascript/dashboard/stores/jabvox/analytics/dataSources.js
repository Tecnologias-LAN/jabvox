import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import { analyticsDataSourcesAPI } from 'dashboard/api/jabvox/analytics';

export const useAnalyticsDataSourcesStore = defineStore(
  'analyticsDataSources',
  {
    state: () => ({
      records: [],
      schemaByDsId: {},
      testResultByDsId: {},
      uiFlags: {
        fetchingList: false,
        creating: false,
        updating: false,
        testing: false,
        fetchingSchema: false,
      },
    }),

    getters: {
      list: state => camelcaseKeys(state.records, { deep: true }),
      find: state => id =>
        camelcaseKeys(state.records.find(r => r.id === Number(id)) || {}, {
          deep: true,
        }),
      schemaFor: state => id => state.schemaByDsId[id],
      testResultFor: state => id => state.testResultByDsId[id],
    },

    actions: {
      async fetch() {
        this.uiFlags.fetchingList = true;
        try {
          const { data } = await analyticsDataSourcesAPI.getAll();
          this.records = data;
        } finally {
          this.uiFlags.fetchingList = false;
        }
      },

      async create(payload) {
        this.uiFlags.creating = true;
        try {
          const { data } = await analyticsDataSourcesAPI.create(payload);
          this.records.push(data);
          return camelcaseKeys(data, { deep: true });
        } finally {
          this.uiFlags.creating = false;
        }
      },

      async update(id, payload) {
        this.uiFlags.updating = true;
        try {
          const { data } = await analyticsDataSourcesAPI.update(id, payload);
          const idx = this.records.findIndex(r => r.id === Number(id));
          if (idx !== -1) this.records.splice(idx, 1, data);
          return camelcaseKeys(data, { deep: true });
        } finally {
          this.uiFlags.updating = false;
        }
      },

      async destroy(id) {
        await analyticsDataSourcesAPI.destroy(id);
        this.records = this.records.filter(r => r.id !== Number(id));
      },

      async testConnection(id) {
        this.uiFlags.testing = true;
        try {
          const { data } = await analyticsDataSourcesAPI.testConnection(id);
          this.testResultByDsId[id] = camelcaseKeys(data, { deep: true });
          return this.testResultByDsId[id];
        } finally {
          this.uiFlags.testing = false;
        }
      },

      async testUnsaved(payload) {
        this.uiFlags.testing = true;
        try {
          const { data } = await analyticsDataSourcesAPI.testUnsaved(payload);
          return camelcaseKeys(data, { deep: true });
        } finally {
          this.uiFlags.testing = false;
        }
      },

      async fetchSchema(id) {
        this.uiFlags.fetchingSchema = true;
        try {
          const { data } = await analyticsDataSourcesAPI.schema(id);
          // El backend responde { schema: [{ name, type, columns }] }. Guardamos el array
          // de tablas, no el sobre completo (si no, schemaFor devolvía {schema:[...]} y la
          // vista buscaba raw.tables → 0 tablas).
          const schema = data?.schema ?? data;
          this.schemaByDsId[id] = camelcaseKeys(schema, { deep: true });
          return this.schemaByDsId[id];
        } finally {
          this.uiFlags.fetchingSchema = false;
        }
      },

      async sync(id) {
        await analyticsDataSourcesAPI.sync(id);
        return this.fetchSchema(id);
      },
    },
  }
);
