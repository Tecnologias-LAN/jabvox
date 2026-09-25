/* global axios */
import ApiClient from '../ApiClient';

const tablesClient = new ApiClient('jabvox/custom_tables', {
  accountScoped: true,
});
const buttonsClient = new ApiClient('jabvox/quick_buttons', {
  accountScoped: true,
});

const contactRowsUrl = contactId =>
  new ApiClient(`jabvox/contacts/${contactId}/custom_table_rows`, {
    accountScoped: true,
  }).url;

export default {
  // Tables
  getTables: () => axios.get(tablesClient.url),
  createTable: data => axios.post(tablesClient.url, { table: data }),
  updateTable: (id, data) =>
    axios.patch(`${tablesClient.url}/${id}`, { table: data }),
  deleteTable: id => axios.delete(`${tablesClient.url}/${id}`),
  exportTable: id => axios.get(`${tablesClient.url}/${id}/export`),
  importTable: data => axios.post(`${tablesClient.url}/import`, { data }),

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

  // Tablas de varias filas (Asesorías, Casos…) ligadas al CONTACTO. Cada fila es un
  // registro independiente; un contacto puede tener muchas por tabla.
  getContactTableRows: contactId => axios.get(contactRowsUrl(contactId)),
  createContactTableRow: (contactId, tableId, data) =>
    axios.post(`${contactRowsUrl(contactId)}/${tableId}`, { data }),
  updateContactTableRow: (contactId, tableId, rowId, data) =>
    axios.patch(`${contactRowsUrl(contactId)}/${tableId}`, {
      row_id: rowId,
      data,
    }),
  deleteContactTableRow: (contactId, tableId, rowId) =>
    axios.delete(`${contactRowsUrl(contactId)}/${tableId}`, {
      params: { row_id: rowId },
    }),

  // Quick Buttons
  getButtons: () => axios.get(buttonsClient.url),
  createButton: data => axios.post(buttonsClient.url, { button: data }),
  updateButton: (id, data) =>
    axios.patch(`${buttonsClient.url}/${id}`, { button: data }),
  deleteButton: id => axios.delete(`${buttonsClient.url}/${id}`),
};
