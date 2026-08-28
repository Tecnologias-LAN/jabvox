/* global axios */
import ApiClient from '../../ApiClient';

// Data sources: CRUD + connection testing, introspection, data preview, query execution.
class JabvoxAnalyticsDataSourcesAPI extends ApiClient {
  constructor() {
    super('jabvox/analytics/data_sources', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { data_source: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { data_source: data });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // Test an already-saved data source.
  testConnection(id) {
    return axios.post(`${this.url}/${id}/test_connection`);
  }

  // Test connection parameters before the source is saved.
  testUnsaved(data) {
    return axios.post(`${this.url}/test_connection`, { data_source: data });
  }

  schema(id) {
    return axios.get(`${this.url}/${id}/schema`);
  }

  preview(id, { table, page = 1, perPage = 100, sort, search, filters } = {}) {
    return axios.get(`${this.url}/${id}/preview`, {
      params: { table, page, per_page: perPage, sort, search, filters },
      // Serializa filtros multi-valor como filters[Columna][]=a&filters[Columna][]=b, que Rails
      // parsea a { filters: { Columna: [a, b] } } (IN en el backend). El serializer por defecto
      // de axios no garantiza este formato para arrays anidados en objetos.
      paramsSerializer: { indexes: null },
    });
  }

  columnValues(id, { table, column, search, limit = 200 } = {}) {
    return axios.get(`${this.url}/${id}/column_values`, {
      params: { table, column, search, limit },
    });
  }

  runQuery(id, spec) {
    return axios.post(`${this.url}/${id}/query`, { query_spec: spec });
  }

  compileSql(id, spec) {
    return axios.post(`${this.url}/${id}/compile_sql`, { query_spec: spec });
  }

  runCustomSql(id, sql, params = {}) {
    return axios.post(`${this.url}/${id}/custom_sql`, { sql, ...params });
  }

  validateSql(id, sql) {
    return axios.post(`${this.url}/${id}/validate_sql`, { sql });
  }

  sync(id) {
    return axios.post(`${this.url}/${id}/sync`);
  }
}

export default new JabvoxAnalyticsDataSourcesAPI();
