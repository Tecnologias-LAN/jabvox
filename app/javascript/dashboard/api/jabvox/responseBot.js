/* global axios */
import ApiClient from '../ApiClient';

const seatsClient = new ApiClient('jabvox/response_bot_seats', {
  accountScoped: true,
});
const rolesClient = new ApiClient('jabvox/response_bot_roles', {
  accountScoped: true,
});
const configsClient = new ApiClient('jabvox/response_bot_configs', {
  accountScoped: true,
});
const documentsClient = new ApiClient('jabvox/response_bot_documents', {
  accountScoped: true,
});

export const responseBotSeatsAPI = {
  getAll: () => axios.get(seatsClient.url),
};

export const responseBotRolesAPI = {
  getAll: () => axios.get(rolesClient.url),
};

export const responseBotConfigsAPI = {
  getAll: () => axios.get(configsClient.url),
  create: data => axios.post(configsClient.url, { config: data }),
  update: (id, data) =>
    axios.patch(`${configsClient.url}/${id}`, { config: data }),
  destroy: id => axios.delete(`${configsClient.url}/${id}`),
  setupLabels: () => axios.post(`${configsClient.url}/setup_labels`),
};

export const responseBotDocumentsAPI = {
  getAll: () => axios.get(documentsClient.url),
  sync: () => axios.post(`${documentsClient.url}/sync`),
  update: (id, data) =>
    axios.patch(`${documentsClient.url}/${id}`, { document: data }),
  destroy: id => axios.delete(`${documentsClient.url}/${id}`),
};
