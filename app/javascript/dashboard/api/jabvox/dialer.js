/* global axios */
import ApiClient from '../ApiClient';

const campaignsClient = new ApiClient('jabvox/dialer_campaigns', {
  accountScoped: true,
});
const logsClient = new ApiClient('jabvox/dialer_call_logs', {
  accountScoped: true,
});

export const dialerCampaignsAPI = {
  getAll: () => axios.get(campaignsClient.url),
  getById: id => axios.get(`${campaignsClient.url}/${id}`),
  create: data => axios.post(campaignsClient.url, { campaign: data }),
  update: (id, data) =>
    axios.patch(`${campaignsClient.url}/${id}`, { campaign: data }),
  destroy: id => axios.delete(`${campaignsClient.url}/${id}`),
  start: id => axios.patch(`${campaignsClient.url}/${id}/start`),
  pause: id => axios.patch(`${campaignsClient.url}/${id}/pause`),
  stop: id => axios.patch(`${campaignsClient.url}/${id}/stop`),
  retryContacts: id =>
    axios.patch(`${campaignsClient.url}/${id}/retry_contacts`),
  getContacts: id => axios.get(`${campaignsClient.url}/${id}/contacts`),
  getCallLogs: id => axios.get(`${campaignsClient.url}/${id}/call_logs`),
  importContacts: (id, contacts) =>
    axios.post(`${campaignsClient.url}/${id}/import_contacts`, { contacts }),
  originate: (id, data) =>
    axios.post(`${campaignsClient.url}/${id}/originate`, data),
  leadCount: params =>
    axios.get(`${campaignsClient.url}/lead_count`, { params }),
  getReport: (id, params) =>
    axios.get(`${campaignsClient.url}/${id}/report`, { params }),
};

export const dialerCallLogsAPI = {
  getAll: () => axios.get(logsClient.url),
  create: data => axios.post(logsClient.url, data),
};

const dialerStatesClient = new ApiClient('jabvox/dialer_states', {
  accountScoped: true,
});
const dialerAccessesClient = new ApiClient('jabvox/dialer_accesses', {
  accountScoped: true,
});

export const dialerStatesAPI = {
  getAll: () => axios.get(dialerStatesClient.url),
  create: data => axios.post(dialerStatesClient.url, data),
  update: (id, data) => axios.patch(`${dialerStatesClient.url}/${id}`, data),
  destroy: id => axios.delete(`${dialerStatesClient.url}/${id}`),
};

export const dialerAccessesAPI = {
  getAll: () => axios.get(dialerAccessesClient.url),
  update: (userId, canAccess) =>
    axios.patch(`${dialerAccessesClient.url}/${userId}`, {
      can_access: canAccess,
    }),
  me: () => axios.get(`${dialerAccessesClient.url}/me`),
  connect: campaignId =>
    axios.post(`${dialerAccessesClient.url}/connect`, {
      campaign_id: campaignId,
    }),
  disconnect: () => axios.delete(`${dialerAccessesClient.url}/connect`),
  updateState: stateId =>
    axios.patch(`${dialerAccessesClient.url}/state`, { state_id: stateId }),
  heartbeat: () => axios.post(`${dialerAccessesClient.url}/heartbeat`),
  requestCall: () => axios.post(`${dialerAccessesClient.url}/request_call`),
  endCall: dialerContactId =>
    axios.patch(`${dialerAccessesClient.url}/end_call`, {
      dialer_contact_id: dialerContactId,
    }),
};
