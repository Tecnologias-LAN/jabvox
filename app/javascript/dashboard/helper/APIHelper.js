import Auth from '../api/auth';
import { clearCookiesOnLogout } from '../store/utils/api';

const parseErrorCode = error => Promise.reject(error);

let ipBlockHandled = false;

async function handleIpBlock() {
  if (ipBlockHandled) return;
  ipBlockHandled = true;

  const match = window.location.pathname.match(/\/app\/accounts\/(\d+)\//);
  const blockedAccountId = match ? parseInt(match[1], 10) : null;

  try {
    const { data } = await Auth.validityCheck();
    const accounts = data?.payload?.data?.accounts || [];
    const other = accounts.find(a => a.id !== blockedAccountId);
    if (other) {
      window.location.href = `/app/accounts/${other.id}/dashboard`;
      return;
    }
  } catch (e) {
    // ignore — fall through to logout
  }

  clearCookiesOnLogout();
  window.location.href = '/app/login';
}

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();
    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => {
      if (
        error.response?.status === 404 &&
        error.response?.data?.error === 'ip_blocked'
      ) {
        handleIpBlock();
      }
      return parseErrorCode(error);
    }
  );
  return wootApi;
};
