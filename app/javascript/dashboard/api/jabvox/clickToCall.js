/* global axios */
import ApiClient from '../ApiClient';

const callsClient = new ApiClient('jabvox/click_to_call/calls', {
  accountScoped: true,
});
const callLogsClient = new ApiClient('jabvox/click_to_call/call_logs', {
  accountScoped: true,
});
const typificationsClient = new ApiClient('jabvox/typifications', {
  accountScoped: true,
});

export const clickToCallAPI = {
  // target: { contact_id } | { lead_id } | { conversation_id }
  initiate: target => axios.post(callsClient.url, target),
  hangup: callLogId => axios.delete(`${callsClient.url}/${callLogId}`),
  typify: (callLogId, payload) =>
    axios.patch(`${callLogsClient.url}/${callLogId}`, { call_log: payload }),
  getLog: callLogId => axios.get(`${callLogsClient.url}/${callLogId}`),
  logs: () => axios.get(callLogsClient.url),
};

export const typificationsAPI = {
  getAll: (activeOnly = false) =>
    axios.get(typificationsClient.url, { params: { active_only: activeOnly } }),
  create: typification => axios.post(typificationsClient.url, { typification }),
  update: (id, typification) =>
    axios.patch(`${typificationsClient.url}/${id}`, { typification }),
  destroy: id => axios.delete(`${typificationsClient.url}/${id}`),
};
