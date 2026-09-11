/* global axios */
import ApiClient from '../ApiClient';

// API de "Saldo IA" por cuenta: ver saldo y crear/listar virtual keys. La key en claro solo
// llega en la respuesta de createKey (una vez); Jabvox no la persiste.
class JabvoxAiBudgetAPI extends ApiClient {
  constructor() {
    super('jabvox/ai_budget', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  keys() {
    return axios.get(`${this.url}/keys`);
  }

  createKey(data) {
    return axios.post(`${this.url}/create_key`, data);
  }
}

export const aiBudgetAPI = new JabvoxAiBudgetAPI();
