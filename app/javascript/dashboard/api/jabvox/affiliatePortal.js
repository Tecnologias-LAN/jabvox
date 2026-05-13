/* global axios */

const BASE = '/api/v1/jabvox/affiliate_portal';

function authHeaders() {
  const token = sessionStorage.getItem('jabvox_affiliate_token');
  return token ? { Authorization: `Bearer ${token}` } : {};
}

export default {
  login: (affiliateSlug, accountCode, authToken) =>
    axios.post(`${BASE}/auth/login`, {
      affiliate_slug: affiliateSlug,
      account_code: accountCode,
      auth_token: authToken,
    }),

  createContact: payload =>
    axios.post(`${BASE}/contacts`, payload, { headers: authHeaders() }),

  importCsv: formData =>
    axios.post(`${BASE}/imports`, formData, {
      headers: { ...authHeaders(), 'Content-Type': 'multipart/form-data' },
    }),

  getLeads: (page = 1) =>
    axios.get(`${BASE}/leads`, {
      params: { page },
      headers: authHeaders(),
    }),

  getHistory: (page = 1) =>
    axios.get(`${BASE}/leads/history`, {
      params: { page },
      headers: authHeaders(),
    }),
};
