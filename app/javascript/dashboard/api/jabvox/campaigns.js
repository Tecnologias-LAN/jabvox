/* global axios */
import ApiClient from '../ApiClient';

class JabvoxCampaignsAPI extends ApiClient {
  constructor() {
    super('jabvox/lead_campaigns', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  create(data) {
    return axios.post(this.url, { campaign: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { campaign: data });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export const campaignsAPI = new JabvoxCampaignsAPI();
