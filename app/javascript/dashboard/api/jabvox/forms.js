/* global axios */
import ApiClient from '../ApiClient';

const formsClient = new ApiClient('jabvox/forms', { accountScoped: true });
const formConfigClient = new ApiClient('jabvox/form_config', {
  accountScoped: true,
});

export const formsAPI = {
  getAll: () => axios.get(formsClient.url),
  getById: id => axios.get(`${formsClient.url}/${id}`),
  create: data => axios.post(formsClient.url, { form: data }),
  update: (id, data) => axios.patch(`${formsClient.url}/${id}`, { form: data }),
  destroy: id => axios.delete(`${formsClient.url}/${id}`),
};

export const formConfigAPI = {
  get: () => axios.get(formConfigClient.url),
  update: data => axios.patch(formConfigClient.url, { form_config: data }),
};
