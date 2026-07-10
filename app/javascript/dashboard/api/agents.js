/* global axios */

import ApiClient from './ApiClient';

class Agents extends ApiClient {
  constructor() {
    super('agents', { accountScoped: true });
  }

  bulkInvite({ emails }) {
    return axios.post(`${this.url}/bulk_create`, {
      emails,
    });
  }

  delete(id, { reassignToId } = {}) {
    return axios.delete(`${this.url}/${id}`, {
      data: reassignToId ? { reassign_to_id: reassignToId } : undefined,
    });
  }
}

export default new Agents();
