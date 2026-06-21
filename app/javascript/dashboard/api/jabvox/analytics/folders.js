import ApiClient from '../../ApiClient';

class JabvoxAnalyticsFoldersAPI extends ApiClient {
  constructor() {
    super('jabvox/analytics/folders', { accountScoped: true });
  }
}

export default new JabvoxAnalyticsFoldersAPI();
