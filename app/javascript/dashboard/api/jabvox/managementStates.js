/* global axios */
import ApiClient from '../ApiClient';

class JabvoxManagementStatesAPI extends ApiClient {
  constructor() {
    super('jabvox/management_states', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  create(data) {
    return axios.post(this.url, { state: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { state: data });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  export() {
    return axios.get(`${this.url}/export`);
  }

  import(data) {
    return axios.post(`${this.url}/import`, { data });
  }
}

export const managementStatesAPI = new JabvoxManagementStatesAPI();
