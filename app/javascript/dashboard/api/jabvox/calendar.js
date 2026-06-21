/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/calendar_events', { accountScoped: true });
const peopleClient = new ApiClient('jabvox/calendar_external_people', {
  accountScoped: true,
});

export default {
  // Events
  getEvents: (params = {}) => axios.get(client.url, { params }),
  // create accepts either { start_at, end_at } or { slots: [...] } plus participants[]
  create: payload => axios.post(client.url, payload),
  update: (id, payload) => axios.patch(`${client.url}/${id}`, payload),
  destroy: (id, params = {}) => axios.delete(`${client.url}/${id}`, { params }),

  // External people (calendar contacts managed in the settings tab)
  getExternalPeople: () => axios.get(peopleClient.url),
  createExternalPerson: payload => axios.post(peopleClient.url, payload),
  updateExternalPerson: (id, payload) =>
    axios.patch(`${peopleClient.url}/${id}`, payload),
  destroyExternalPerson: id => axios.delete(`${peopleClient.url}/${id}`),
};
