/* global axios */
import ApiClient from '../ApiClient';

const providersClient = new ApiClient('jabvox/sms_providers', {
  accountScoped: true,
});
const campaignsClient = new ApiClient('jabvox/sms_campaigns', {
  accountScoped: true,
});
const messagesClient = new ApiClient('jabvox/sms_messages', {
  accountScoped: true,
});

export const smsProvidersAPI = {
  getAll: () => axios.get(providersClient.url),
  getById: id => axios.get(`${providersClient.url}/${id}`),
  create: data => axios.post(providersClient.url, { provider: data }),
  update: (id, data) =>
    axios.patch(`${providersClient.url}/${id}`, { provider: data }),
  destroy: id => axios.delete(`${providersClient.url}/${id}`),
  checkConnection: id =>
    axios.get(`${providersClient.url}/${id}/check_connection`),
};

export const smsCampaignsAPI = {
  getAll: () => axios.get(campaignsClient.url),
  getById: id => axios.get(`${campaignsClient.url}/${id}`),
  create: data => axios.post(campaignsClient.url, { campaign: data }),
  update: (id, data) =>
    axios.patch(`${campaignsClient.url}/${id}`, { campaign: data }),
  destroy: id => axios.delete(`${campaignsClient.url}/${id}`),
  sendBulk: id => axios.post(`${campaignsClient.url}/${id}/send_bulk`),
  getContacts: () => axios.get(`${campaignsClient.url}/contacts`),
  leadCount: params =>
    axios.get(`${campaignsClient.url}/lead_count`, { params }),
};

export const smsMessagesAPI = {
  getAll: (params = {}) => axios.get(messagesClient.url, { params }),
  getStats: () => axios.get(`${messagesClient.url}/stats`),
  sendToContact: payload =>
    axios.post(`${messagesClient.url}/send_to_contact`, payload),
};
