// devise-token-auth exige access-token/client/uid en cada request. `fetch()` y
// `navigator.sendBeacon()` no los añaden solos (a diferencia de axios, que ya los lleva
// inyectados en sus defaults desde el login — ver helper/APIHelper.js), así que estos pocos
// puntos del código que no pueden usar axios (streaming SSE, beacons al cerrar pestaña) los
// necesitan reconstruir a mano.
//
// Se leen de `window.axios.defaults.headers.common` — el estado YA vive ahí, en memoria de
// JS, poblado una sola vez al cargar la app (helper/APIHelper.js). Es la misma fuente de
// verdad que usa el resto de la app para autenticar cada request; no hay necesidad de volver
// a tocar `document.cookie` en cada llamada, lo que evita reexponer el token por ese canal
// además de reducirlo a un solo punto de lectura en vez de siete.
export function deviseAuthHeaders() {
  const common = window.axios?.defaults?.headers?.common || {};
  const accessToken = common['access-token'];
  if (!accessToken) return {};
  return {
    'access-token': accessToken,
    client: common.client || '',
    uid: common.uid || '',
    expiry: common.expiry || '',
    'token-type': common['token-type'] || 'Bearer',
  };
}
