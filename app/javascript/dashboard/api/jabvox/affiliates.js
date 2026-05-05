/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/affiliates', { accountScoped: true });

export default {
  getAll: () => axios.get(client.url),
  create: payload => axios.post(client.url, payload),
  update: (id, payload) => axios.patch(`${client.url}/${id}`, payload),
  destroy: id => axios.delete(`${client.url}/${id}`),
  regenerateToken: id => axios.patch(`${client.url}/${id}/regenerate_token`),
  regenerateCode: id => axios.patch(`${client.url}/${id}/regenerate_code`),
  getPortalLoginUrl: () => axios.get(`${client.url}/portal_login_url`),
  getIpWhitelist: affiliateId =>
    axios.get(`${client.url}/${affiliateId}/affiliate_ip_whitelists`),
  addIp: (affiliateId, payload) =>
    axios.post(`${client.url}/${affiliateId}/affiliate_ip_whitelists`, {
      jabvox_affiliate_ip_whitelist: payload,
    }),
  updateIp: (affiliateId, ipId, payload) =>
    axios.patch(
      `${client.url}/${affiliateId}/affiliate_ip_whitelists/${ipId}`,
      { jabvox_affiliate_ip_whitelist: payload }
    ),
  destroyIp: (affiliateId, ipId) =>
    axios.delete(
      `${client.url}/${affiliateId}/affiliate_ip_whitelists/${ipId}`
    ),
};
