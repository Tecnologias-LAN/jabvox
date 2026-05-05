/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/field_visibilities', {
  accountScoped: true,
});

export default {
  getAll: () => axios.get(client.url),
  getMe: () => axios.get(`${client.url}/me`),
  update: (userId, fieldName, canView) =>
    axios.patch(client.url, {
      user_id: userId,
      field_name: fieldName,
      can_view: canView,
    }),
};
