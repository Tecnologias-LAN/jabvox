/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/calendar_events', { accountScoped: true });

export default {
  getEvents: (params = {}) => axios.get(client.url, { params }),
  create: payload => axios.post(client.url, payload),
  update: (id, payload) => axios.patch(`${client.url}/${id}`, payload),
  destroy: id => axios.delete(`${client.url}/${id}`),
};
