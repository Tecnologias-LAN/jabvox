/* global axios */
import ApiClient from '../../ApiClient';

class JabvoxAnalyticsExportsAPI extends ApiClient {
  constructor() {
    super('jabvox/analytics/exports', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { export: data });
  }
}

export default new JabvoxAnalyticsExportsAPI();
