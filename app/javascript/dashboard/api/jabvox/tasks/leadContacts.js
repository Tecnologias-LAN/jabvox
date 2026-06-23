/* global axios */
import ApiClient from '../../ApiClient';

// Lead contacts: info-only reference people attached to a lead (right panel).
class JabvoxTaskLeadContactsAPI extends ApiClient {
  constructor() {
    super('jabvox/tasks/lead_contacts', { accountScoped: true });
  }

  getAll(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { lead_contact: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { lead_contact: data });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new JabvoxTaskLeadContactsAPI();
