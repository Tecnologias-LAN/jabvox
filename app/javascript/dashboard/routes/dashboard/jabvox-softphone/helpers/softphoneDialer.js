import { emitter } from 'shared/helpers/mitt';
import store from 'dashboard/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

/**
 * ¿El softphone está activo para la cuenta actual?
 * @returns {boolean}
 */
export function isSoftphoneEnabled() {
  const accountId = store.getters.getCurrentAccountId;
  return store.getters['accounts/isFeatureEnabledonAccount'](
    accountId,
    FEATURE_FLAGS.JABVOX_SOFTPHONE
  );
}

/**
 * Punto único para enrutar una llamada SALIENTE al softphone WebRTC.
 *
 * Un origen (click-to-call o manual) llama a dialViaSoftphone(number, meta). Si el módulo
 * jabvox_softphone está activo para la cuenta, emite el evento que el softphone escucha y
 * devuelve true (el origen NO debe hacer el originate AMI). Si no está activo, devuelve
 * false y el origen sigue con su flujo habitual.
 *
 * Nota sobre el DIALER: el dialer es server-driven (Asterisk marca a la extensión del
 * agente por AMI). Como el softphone registra ESA misma extensión en Asterisk, la llamada
 * del dialer entra al softphone como INVITE entrante (SipClient#onInvite) sin necesidad de
 * pasar por este helper. La integración del dialer ocurre a nivel de PBX (ext = softphone).
 *
 * @param {string} number - Número o extensión a marcar.
 * @param {{ name?: string }} [meta]
 * @returns {boolean} true si el softphone tomó la llamada.
 */
export function dialViaSoftphone(number, meta = {}) {
  if (!number) return false;
  if (!isSoftphoneEnabled()) return false;

  emitter.emit('jabvox.softphone.dial', { number, name: meta.name || '' });
  return true;
}
