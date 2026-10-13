/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/dashboard', { accountScoped: true });

export default {
  getSummary: params => axios.get(client.url, { params }),
};
