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
        const page = opts.page ?? this.result.page;
        const perPage = opts.perPage ?? this.result.perPage;
        const { data } = await analyticsDataSourcesAPI.preview(dsId, {
          table: opts.table ?? this.spec.table,
          page,
          perPage,
          sort: opts.sort ?? this.result.sort,
          search: opts.search ?? this.result.search,
          filters: opts.filters,
        });
        const camel = camelcaseKeys(data, { deep: true });
        // El backend devuelve `row_count` (→ rowCount). La UI usa `total` para paginar; hay
        // que mapearlo explícitamente o el contador queda en 0 ("25 of 0 rows"). Guardamos
        // también page/perPage usados para que la paginación conozca su estado.
        this.result = {
          ...this.result,
          rows: camel.rows,
          columns: camel.columns,
          total: camel.rowCount ?? camel.total ?? 0,
          page,
          perPage,
        };
        return this.result;
      } catch (error) {
        // Si el preview falla (p.ej. la BD externa está caída), NO dejar en pantalla los
        // datos de una consulta anterior: se limpia el resultado y se relanza el error para
        // que la vista muestre el aviso de conexión.
        this.result = { ...this.result, rows: [], columns: [], total: 0 };
        throw error;
      } finally {
        this.uiFlags.previewing = false;
      }
    },

    // Compila un spec visual a SQL (sin ejecutar), para la conversión visual→SQL del editor.
    async compileSql(dsId, spec) {
      const { data } = await analyticsDataSourcesAPI.compileSql(dsId, spec);
      return data.sql;
    },

    // Valores distintos de una columna para los filtros seleccionables del visor de datos.
    async fetchColumnValues(dsId, { table, column, search, limit } = {}) {
      const { data } = await analyticsDataSourcesAPI.columnValues(dsId, {
        table,
        column,
        search,
        limit,
      });
      return camelcaseKeys(data, { deep: true });
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
      } catch (error) {
        this.result = { ...this.result, rows: [], columns: [], total: 0 };
        throw error;
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
      } catch (error) {
        this.result = { ...this.result, rows: [], columns: [], total: 0 };
        throw error;
      } finally {
        this.uiFlags.running = false;
      }
    },
  },
});
