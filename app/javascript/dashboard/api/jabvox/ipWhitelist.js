/* global axios */
import ApiClient from '../ApiClient';

class JabvoxIpWhitelistAPI extends ApiClient {
  constructor() {
    super('jabvox/ip_whitelists', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  create(data) {
    return axios.post(this.url, { jabvox_ip_whitelist: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { jabvox_ip_whitelist: data });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export const ipWhitelistAPI = new JabvoxIpWhitelistAPI();
