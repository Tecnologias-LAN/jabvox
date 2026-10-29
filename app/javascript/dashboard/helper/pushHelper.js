/* eslint-disable no-console */
import NotificationSubscriptions from '../api/notificationSubscription';
import auth from '../api/auth';
import { useAlert } from 'dashboard/composables';

export const verifyServiceWorkerExistence = (callback = () => {}) => {
  if (!('serviceWorker' in navigator)) {
    // Service Worker isn't supported on this browser, disable or hide UI.
    return;
  }

  if (!('PushManager' in window)) {
    // Push isn't supported on this browser, disable or hide UI.
    return;
  }

  navigator.serviceWorker
    .register('/sw.js')
    .then(registration => callback(registration))
    .catch(registrationError => {
      // eslint-disable-next-line
      console.log('SW registration failed: ', registrationError);
    });
};

export const hasPushPermissions = () => {
  if ('Notification' in window) {
    return Notification.permission === 'granted';
  }
  return false;
};

const generateKeys = str =>
  btoa(String.fromCharCode.apply(null, new Uint8Array(str)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

// Convierte la clave VAPID pública (string base64url) al Uint8Array de 65 bytes
// (empezando por 0x04) que exige la Push API. Chrome/Edge toleran otros formatos,
// pero Firefox/Safari rechazan cualquier cosa que no sea exactamente esto, que era
// la causa de que el push "solo funcionara en Chrome".
export const urlBase64ToUint8Array = base64String => {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i += 1) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
};

// La clave puede llegar como string base64url (nuevo formato) o como Uint8Array/array
// serializado (compatibilidad con lo que ya estaba inyectado). Normaliza a BufferSource.
const applicationServerKey = () => {
  const key = window.jabvoxConfig?.vapidPublicKey;
  if (!key) return null;
  if (typeof key === 'string') return urlBase64ToUint8Array(key);
  // Ya es un Uint8Array o un array de bytes (formato antiguo).
  return key instanceof Uint8Array ? key : new Uint8Array(key);
};

export const getPushSubscriptionPayload = subscription => ({
  subscription_type: 'browser_push',
  subscription_attributes: {
    endpoint: subscription.endpoint,
    p256dh: generateKeys(subscription.getKey('p256dh')),
    auth: generateKeys(subscription.getKey('auth')),
  },
});

export const sendRegistrationToServer = subscription => {
  if (auth.hasAuthCookie()) {
    return NotificationSubscriptions.create(
      getPushSubscriptionPayload(subscription)
    );
  }
  return null;
};

// User-facing messages. Callers may override via the `messages` option to pass
// localized strings (the components have i18n); these are the Spanish defaults.
const PUSH_MESSAGES = {
  vapidMissing:
    'Las notificaciones push no están configuradas en el servidor (falta la clave VAPID).',
  subscribeFailed:
    'No se pudo activar las notificaciones push en este navegador.',
  insecureContext:
    'Las notificaciones push requieren HTTPS (o localhost). Abre la app por https:// o http://localhost.',
  unsupported: 'Este navegador no soporta notificaciones push.',
  permissionDenied:
    'Bloqueaste las notificaciones. Actívalas en los permisos del sitio en tu navegador y vuelve a intentar.',
};

export const registerSubscription = (
  onSuccess = () => {},
  messages = {},
  onError = () => {}
) => {
  const msg = { ...PUSH_MESSAGES, ...messages };
  const serverKey = applicationServerKey();
  // Without a VAPID public key the browser can't be subscribed. Surface it
  // instead of failing silently (common cause of a "dead" enable button).
  if (!serverKey) {
    // eslint-disable-next-line no-console
    console.error(
      '[push] Missing window.jabvoxConfig.vapidPublicKey — push cannot be enabled.'
    );
    useAlert(msg.vapidMissing);
    onError();
    return;
  }
  const subscribe = registration =>
    registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: serverKey,
    });

  // Si ya existe una suscripción con OTRA applicationServerKey (VAPID cambió), el navegador
  // lanza InvalidStateError. La solución es desuscribir la existente y volver a suscribir.
  const subscribeWithRetry = registration =>
    subscribe(registration).catch(error => {
      if (error?.name !== 'InvalidStateError') throw error;
      return registration.pushManager
        .getSubscription()
        .then(existing => (existing ? existing.unsubscribe() : null))
        .then(() => subscribe(registration));
    });

  navigator.serviceWorker.ready
    .then(subscribeWithRetry)
    .then(sendRegistrationToServer)
    .then(() => {
      onSuccess();
    })
    .catch(error => {
      // eslint-disable-next-line no-console
      console.error('Push subscription registration failed:', error);
      useAlert(msg.subscribeFailed);
      onError();
    });
};

// `onError` permite al componente revertir el toggle cuando la activación falla
// (antes el switch quedaba encendido aunque el push no se hubiera activado).
export const requestPushPermissions = ({
  onSuccess,
  messages = {},
  onError = () => {},
}) => {
  const msg = { ...PUSH_MESSAGES, ...messages };
  // Push requires a secure context (HTTPS, or localhost in dev). Browsers do
  // nothing — and show no prompt — when this isn't met, so explain it.
  if (!window.isSecureContext) {
    useAlert(msg.insecureContext);
    onError();
    return;
  }
  if (!('Notification' in window)) {
    useAlert(msg.unsupported);
    onError();
    return;
  }
  if (Notification.permission === 'granted') {
    registerSubscription(onSuccess, messages, onError);
  } else if (Notification.permission === 'denied') {
    // The browser won't re-prompt once denied; the user must reset it manually.
    useAlert(msg.permissionDenied);
    onError();
  } else {
    Notification.requestPermission().then(permission => {
      if (permission === 'granted') {
        registerSubscription(onSuccess, messages, onError);
      } else if (permission === 'denied') {
        useAlert(msg.permissionDenied);
        onError();
      } else {
        // 'default' = el usuario cerró el prompt sin decidir: también revertir.
        onError();
      }
    });
  }
};
