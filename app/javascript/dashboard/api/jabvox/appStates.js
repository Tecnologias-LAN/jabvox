/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/app_states', { accountScoped: true });

export default {
  getAll: () => axios.get(client.url),
  create: params => axios.post(client.url, params),
  update: (id, params) => axios.patch(`${client.url}/${id}`, params),
  destroy: id => axios.delete(`${client.url}/${id}`),
  setPresence: appStateId =>
    axios.patch(`${client.url}/set_presence`, { app_state_id: appStateId }),
};
