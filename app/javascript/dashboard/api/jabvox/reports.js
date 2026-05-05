/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/reports', { accountScoped: true });

export default {
  getProducts: (params = {}) => axios.get(`${client.url}/products`, { params }),
  getAgents: (params = {}) => axios.get(`${client.url}/agents`, { params }),
  getDialer: (params = {}) => axios.get(`${client.url}/dialer`, { params }),
  getAgentStatus: () => axios.get(`${client.url}/agent_status`),
  setDialerState: state =>
    axios.patch(`${client.url}/set_dialer_state`, { state }),
};
