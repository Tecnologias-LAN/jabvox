/* global axios */
import ApiClient from '../ApiClient';

const productsClient = new ApiClient('jabvox/products', {
  accountScoped: true,
});
const salesReportsClient = new ApiClient('jabvox/sales_reports', {
  accountScoped: true,
});
const discountsClient = new ApiClient('jabvox/discounts', {
  accountScoped: true,
});
const orderStatusClient = new ApiClient('jabvox/order_status_configs', {
  accountScoped: true,
});
const currenciesClient = new ApiClient('jabvox/currencies', {
  accountScoped: true,
});
const itemTypesClient = new ApiClient('jabvox/item_types', {
  accountScoped: true,
});
const unitsClient = new ApiClient('jabvox/units_of_measure', {
  accountScoped: true,
});
const taxRatesClient = new ApiClient('jabvox/tax_rates', {
  accountScoped: true,
});
const integrationConfigClient = new ApiClient('jabvox/integration_config', {
  accountScoped: true,
});
const salesReportAccessClient = new ApiClient('jabvox/sales_report_accesses', {
  accountScoped: true,
});
const voipConfigClient = new ApiClient('jabvox/voip_config', {
  accountScoped: true,
});

export const productsAPI = {
  getAll: (params = {}) => axios.get(productsClient.url, { params }),
  getById: id => axios.get(`${productsClient.url}/${id}`),
  create: data => axios.post(productsClient.url, data),
  update: (id, data) => axios.patch(`${productsClient.url}/${id}`, data),
  destroy: id => axios.delete(`${productsClient.url}/${id}`),
  import: () => axios.post(`${productsClient.url}/import`),
};

export const salesReportsAPI = {
  get: (params = {}) => axios.get(salesReportsClient.url, { params }),
};

export const discountsAPI = {
  getAll: () => axios.get(discountsClient.url),
  create: data => axios.post(discountsClient.url, data),
  update: (id, data) => axios.patch(`${discountsClient.url}/${id}`, data),
  destroy: id => axios.delete(`${discountsClient.url}/${id}`),
};

export const orderStatusConfigsAPI = {
  getAll: () => axios.get(orderStatusClient.url),
  create: data => axios.post(orderStatusClient.url, data),
  update: (id, data) => axios.patch(`${orderStatusClient.url}/${id}`, data),
  destroy: id => axios.delete(`${orderStatusClient.url}/${id}`),
};

export const currenciesAPI = {
  getAll: () => axios.get(currenciesClient.url),
  create: data => axios.post(currenciesClient.url, data),
  update: (id, data) => axios.patch(`${currenciesClient.url}/${id}`, data),
  destroy: id => axios.delete(`${currenciesClient.url}/${id}`),
};

export const itemTypesAPI = {
  getAll: () => axios.get(itemTypesClient.url),
  create: data => axios.post(itemTypesClient.url, data),
  update: (id, data) => axios.patch(`${itemTypesClient.url}/${id}`, data),
  destroy: id => axios.delete(`${itemTypesClient.url}/${id}`),
};

export const unitsOfMeasureAPI = {
  getAll: () => axios.get(unitsClient.url),
  create: data => axios.post(unitsClient.url, data),
  update: (id, data) => axios.patch(`${unitsClient.url}/${id}`, data),
  destroy: id => axios.delete(`${unitsClient.url}/${id}`),
};

export const taxRatesAPI = {
  getAll: () => axios.get(taxRatesClient.url),
  create: data => axios.post(taxRatesClient.url, data),
  update: (id, data) => axios.patch(`${taxRatesClient.url}/${id}`, data),
  destroy: id => axios.delete(`${taxRatesClient.url}/${id}`),
};

export const integrationConfigAPI = {
  get: () => axios.get(integrationConfigClient.url),
  update: data => axios.patch(integrationConfigClient.url, data),
  destroy: () => axios.delete(integrationConfigClient.url),
};

export const salesReportAccessAPI = {
  getAll: () => axios.get(salesReportAccessClient.url),
  me: () => axios.get(`${salesReportAccessClient.url}/me`),
  update: (userId, canView) =>
    axios.patch(`${salesReportAccessClient.url}/${userId}`, {
      can_view_reports: canView,
    }),
};

export const voipConfigAPI = {
  get: () => axios.get(voipConfigClient.url),
  update: data => axios.patch(voipConfigClient.url, { config: data }),
  status: () =>
    axios.get(voipConfigClient.url.replace('/voip_config', '/voip_status')),
  originate: (phone, extension, callerId = null, contactId = null) => {
    const data = { phone, extension };
    if (callerId) data.caller_id = callerId;
    if (contactId) data.contact_id = contactId;
    return axios.post(
      voipConfigClient.url.replace('/voip_config', '/voip_originate'),
      data
    );
  },
};
