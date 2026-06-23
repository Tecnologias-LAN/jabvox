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

  // Lead custom fields (JSONB inline on jabvox_leads)
  updateLeadCustomFields: (leadId, customFields) => {
    const leadsClient = new ApiClient(`jabvox/leads/${leadId}/custom_fields`, {
      accountScoped: true,
    });
    return axios.patch(leadsClient.url, { custom_fields: customFields });
  },

  // Quick Buttons
  getButtons: () => axios.get(buttonsClient.url),
  createButton: data => axios.post(buttonsClient.url, { button: data }),
  updateButton: (id, data) =>
    axios.patch(`${buttonsClient.url}/${id}`, { button: data }),
  deleteButton: id => axios.delete(`${buttonsClient.url}/${id}`),
};
