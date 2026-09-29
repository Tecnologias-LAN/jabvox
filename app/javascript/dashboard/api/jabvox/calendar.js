/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/calendar_events', { accountScoped: true });
const peopleClient = new ApiClient('jabvox/calendar_external_people', {
  accountScoped: true,
});
const availabilityClient = new ApiClient('jabvox/agent_availabilities', {
  accountScoped: true,
});
// Sedes: zona horaria y horario comercial que la agenda sombrea.
const branchesClient = new ApiClient('jabvox/branches', {
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

  // Agent working hours (availability) used by Jabvox IA to offer appointment slots
  getAgentsAvailability: () => axios.get(availabilityClient.url),
  getAgentAvailability: agentId =>
    axios.get(`${availabilityClient.url}/${agentId}`),
  updateAgentAvailability: (agentId, availabilities) =>
    axios.patch(`${availabilityClient.url}/${agentId}`, { availabilities }),

  // Sedes (solo el admin las crea y edita; leerlas está abierto)
  getBranches: () => axios.get(branchesClient.url),
  createBranch: payload => axios.post(branchesClient.url, payload),
  updateBranch: (id, payload) =>
    axios.patch(`${branchesClient.url}/${id}`, payload),
  destroyBranch: id => axios.delete(`${branchesClient.url}/${id}`),
};
