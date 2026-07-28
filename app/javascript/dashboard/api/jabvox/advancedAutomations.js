/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/advanced_automations', {
  accountScoped: true,
});
const base = client.url;

// Emisor de SSO del modulo embebido. El secreto nunca llega al navegador: el
// backend devuelve solo la URL del iframe con el JWT ya firmado en el query.
export const advancedAutomationsAPI = {
  // theme: 'light' | 'dark' → se propaga al iframe por query.
  ssoToken: (theme = 'light') => axios.post(`${base}/sso_token`, { theme }),
  // Comprobacion de permisos continua solicitada por el iframe (postMessage).
  permissionsCheck: () => axios.get(`${base}/permissions_check`),
};
