/* global axios */
import ApiClient from '../ApiClient';

const tablesClient = new ApiClient('jabvox/custom_tables', {
  accountScoped: true,
});
const buttonsClient = new ApiClient('jabvox/quick_buttons', {
  accountScoped: true,
});

export default {
  // Tables
  getTables: () => axios.get(tablesClient.url),
  createTable: data => axios.post(tablesClient.url, { table: data }),
  updateTable: (id, data) =>
    axios.patch(`${tablesClient.url}/${id}`, { table: data }),
  deleteTable: id => axios.delete(`${tablesClient.url}/${id}`),

  // Columns (nested under tables)
  getColumns: tableId =>
    axios.get(`${tablesClient.url}/${tableId}/custom_columns`),
  createColumn: (tableId, data) =>
    axios.post(`${tablesClient.url}/${tableId}/custom_columns`, {
      column: data,
    }),
  updateColumn: (tableId, columnId, data) =>
    axios.patch(`${tablesClient.url}/${tableId}/custom_columns/${columnId}`, {
      column: data,
    }),
  deleteColumn: (tableId, columnId) =>
    axios.delete(`${tablesClient.url}/${tableId}/custom_columns/${columnId}`),

  // Standalone table rows (records). Nested under a table's /data endpoint.
  getTableData: tableId => axios.get(`${tablesClient.url}/${tableId}/data`),
  createRow: (tableId, data) =>
    axios.post(`${tablesClient.url}/${tableId}/data`, { data }),
  updateRow: (tableId, rowId, data) =>
    axios.patch(`${tablesClient.url}/${tableId}/data/${rowId}`, { data }),
  deleteRow: (tableId, rowId) =>
    axios.delete(`${tablesClient.url}/${tableId}/data/${rowId}`),

  // Lead custom fields (JSONB inline on jabvox_leads)
  updateLeadCustomFields: (leadId, customFields) => {
    const leadsClient = new ApiClient(`jabvox/leads/${leadId}/custom_fields`, {
      accountScoped: true,
    });
    return axios.patch(leadsClient.url, { custom_fields: customFields });
  },

  // Multi-row tables (Asesorías, Casos…) attached to a lead. Each row is an
  // independent record; a lead can have many per table.
  getLeadTableRows: leadId => {
    const c = new ApiClient(`jabvox/leads/${leadId}/custom_table_rows`, {
      accountScoped: true,
    });
    return axios.get(c.url);
  },
  createLeadTableRow: (leadId, tableId, data) => {
    const c = new ApiClient(`jabvox/leads/${leadId}/custom_table_rows`, {
      accountScoped: true,
    });
    return axios.post(`${c.url}/${tableId}`, { data });
  },
  updateLeadTableRow: (leadId, tableId, rowId, data) => {
    const c = new ApiClient(`jabvox/leads/${leadId}/custom_table_rows`, {
      accountScoped: true,
    });
    return axios.patch(`${c.url}/${tableId}`, { row_id: rowId, data });
  },
  deleteLeadTableRow: (leadId, tableId, rowId) => {
    const c = new ApiClient(`jabvox/leads/${leadId}/custom_table_rows`, {
      accountScoped: true,
    });
    return axios.delete(`${c.url}/${tableId}`, { params: { row_id: rowId } });
  },

  // Quick Buttons
  getButtons: () => axios.get(buttonsClient.url),
  createButton: data => axios.post(buttonsClient.url, { button: data }),
  updateButton: (id, data) =>
    axios.patch(`${buttonsClient.url}/${id}`, { button: data }),
  deleteButton: id => axios.delete(`${buttonsClient.url}/${id}`),
};
