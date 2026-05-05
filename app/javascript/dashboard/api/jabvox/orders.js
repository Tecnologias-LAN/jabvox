/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/orders', { accountScoped: true });

export default {
  getAll: (params = {}) => axios.get(client.url, { params }),
  create: data => axios.post(client.url, data),
  update: (id, data) => axios.patch(`${client.url}/${id}`, data),
  destroy: id => axios.delete(`${client.url}/${id}`),
  sendToAlegra: id => axios.post(`${client.url}/${id}/send_to_alegra`),
};
