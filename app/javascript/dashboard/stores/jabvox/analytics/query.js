import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import { analyticsDataSourcesAPI } from 'dashboard/api/jabvox/analytics';

// Drives the data viewer, visual query builder and custom SQL editor.
export const useAnalyticsQueryStore = defineStore('analyticsQuery', {
  state: () => ({
    spec: {
      table: null,
      columns: [],
      joins: [],
      filters: [],
      aggregations: [],
      groupBy: null,
      dateBucket: null,
    },
    result: {
      rows: [],
      columns: [],
      page: 1,
      perPage: 100,
      total: 0,
      sort: null,
      search: '',
    },
    sql: '',
    validation: null,
    uiFlags: { running: false, validating: false, previewing: false },
  }),

  actions: {
    setSpec(partial) {
      this.spec = { ...this.spec, ...partial };
    },

    resetResult() {
      this.result = {
        rows: [],
        columns: [],
        page: 1,
        perPage: 100,
        total: 0,
        sort: null,
        search: '',
      };
    },

    async previewTable(dsId, opts = {}) {
      this.uiFlags.previewing = true;
      try {
        const { data } = await analyticsDataSourcesAPI.preview(dsId, {
          table: opts.table ?? this.spec.table,
          page: opts.page ?? this.result.page,
          perPage: opts.perPage ?? this.result.perPage,
          sort: opts.sort ?? this.result.sort,
          search: opts.search ?? this.result.search,
          filters: opts.filters,
        });
        this.result = {
          ...this.result,
          ...camelcaseKeys(data, { deep: true }),
        };
        return this.result;
      } finally {
        this.uiFlags.previewing = false;
      }
    },

    async runVisualQuery(dsId) {
      this.uiFlags.running = true;
      try {
        const { data } = await analyticsDataSourcesAPI.runQuery(
          dsId,
          this.spec
        );
        const camel = camelcaseKeys(data, { deep: true });
        this.result = {
          ...this.result,
          rows: camel.rows,
          columns: camel.columns,
          total: camel.rowCount,
        };
        return camel;
      } finally {
        this.uiFlags.running = false;
      }
    },

    async validateSql(dsId) {
      this.uiFlags.validating = true;
      try {
        const { data } = await analyticsDataSourcesAPI.validateSql(
          dsId,
          this.sql
        );
        this.validation = camelcaseKeys(data, { deep: true });
        return this.validation;
      } finally {
        this.uiFlags.validating = false;
      }
    },

    async runSql(dsId) {
      this.uiFlags.running = true;
      try {
        const { data } = await analyticsDataSourcesAPI.runCustomSql(
          dsId,
          this.sql
        );
        const camel = camelcaseKeys(data, { deep: true });
        this.result = {
          ...this.result,
          rows: camel.rows,
          columns: camel.columns,
          total: camel.rowCount,
        };
        return camel;
      } finally {
        this.uiFlags.running = false;
      }
    },
  },
});
