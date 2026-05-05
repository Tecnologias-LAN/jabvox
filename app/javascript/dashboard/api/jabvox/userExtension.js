/* global axios */
import ApiClient from '../ApiClient';

class UserExtensionAPI extends ApiClient {
  constructor() {
    super('jabvox/user_extension', { accountScoped: true });
  }

  // Current user's extension
  getMine() {
    return axios.get(this.url);
  }

  // Admin: list all
  getAll() {
    return axios.get(`${this.baseUrl()}/jabvox/user_extensions`);
  }

  // Admin: assign extension to user
  create(userId, extension) {
    return axios.post(`${this.baseUrl()}/jabvox/user_extensions`, {
      user_id: userId,
      extension,
    });
  }

  // Admin: remove extension
  destroy(id) {
    return axios.delete(`${this.baseUrl()}/jabvox/user_extensions/${id}`);
  }
}

export default new UserExtensionAPI();
