/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/lead_campaigns', { accountScoped: true });

export default {
  getAll: () => axios.get(client.url),
};
