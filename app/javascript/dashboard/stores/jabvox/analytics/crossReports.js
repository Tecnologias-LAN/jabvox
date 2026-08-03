import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import { analyticsCrossReportsAPI } from 'dashboard/api/jabvox/analytics';

// Cross-source reports: join data from several data sources by a mapped common field.
export const useAnalyticsCrossReportsStore = defineStore(
  'analyticsCrossReports',
  {
    state: () => ({
      records: [],
      current: null,
      resultById: {},
      uiFlags: {
        fetchingList: false,
        fetchingOne: false,
        saving: false,
        executing: false,
      },
    }),

    getters: {
      list: state => camelcaseKeys(state.records, { deep: true }),
      resultFor: state => id => state.resultById[id],
    },

    actions: {
      async fetch() {
        this.uiFlags.fetchingList = true;
        try {
          const { data } = await analyticsCrossReportsAPI.getAll();
          this.records = data;
        } finally {
          this.uiFlags.fetchingList = false;
        }
      },

      async show(id) {
        this.uiFlags.fetchingOne = true;
        try {
          const { data } = await analyticsCrossReportsAPI.show(id);
          this.current = camelcaseKeys(data, { deep: true });
          return this.current;
        } finally {
          this.uiFlags.fetchingOne = false;
        }
      },

      async create(payload) {
        this.uiFlags.saving = true;
        try {
          const { data } = await analyticsCrossReportsAPI.create(payload);
          this.records.push(data);
          return camelcaseKeys(data, { deep: true });
        } finally {
          this.uiFlags.saving = false;
        }
      },

      async update(id, payload) {
        this.uiFlags.saving = true;
        try {
          const { data } = await analyticsCrossReportsAPI.update(id, payload);
          const idx = this.records.findIndex(r => r.id === Number(id));
          if (idx !== -1) this.records.splice(idx, 1, data);
          return camelcaseKeys(data, { deep: true });
        } finally {
          this.uiFlags.saving = false;
        }
      },

      async destroy(id) {
        await analyticsCrossReportsAPI.destroy(id);
        this.records = this.records.filter(r => r.id !== Number(id));
      },

      async execute(id) {
        this.uiFlags.executing = true;
        try {
          const { data } = await analyticsCrossReportsAPI.execute(id);
          this.resultById[id] = data; // keep raw columns/rows for the table
          return data;
        } finally {
          this.uiFlags.executing = false;
        }
      },
    },
  }
);
