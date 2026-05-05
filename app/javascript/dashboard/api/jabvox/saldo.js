/* global axios */
import ApiClient from '../ApiClient';

class JabvoxSaldoAPI extends ApiClient {
  constructor() {
    super('jabvox/saldo_config', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  update(data) {
    return axios.patch(this.url, { config: data });
  }

  status() {
    return axios.get(this.url.replace('/saldo_config', '/saldo_balance'));
  }
}

export const saldoAPI = new JabvoxSaldoAPI();
