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

export const registerSubscription = (onSuccess = () => {}, messages = {}) => {
  const msg = { ...PUSH_MESSAGES, ...messages };
  // Without a VAPID public key the browser can't be subscribed. Surface it
  // instead of failing silently (common cause of a "dead" enable button).
  if (!window.jabvoxConfig?.vapidPublicKey) {
    // eslint-disable-next-line no-console
    console.error(
      '[push] Missing window.jabvoxConfig.vapidPublicKey — push cannot be enabled.'
    );
    useAlert(msg.vapidMissing);
    return;
  }
  navigator.serviceWorker.ready
    .then(serviceWorkerRegistration =>
      serviceWorkerRegistration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: window.jabvoxConfig.vapidPublicKey,
      })
    )
    .then(sendRegistrationToServer)
    .then(() => {
      onSuccess();
    })
    .catch(error => {
      // eslint-disable-next-line no-console
      console.error('Push subscription registration failed:', error);
      useAlert(msg.subscribeFailed);
    });
};

export const requestPushPermissions = ({ onSuccess, messages = {} }) => {
  const msg = { ...PUSH_MESSAGES, ...messages };
  // Push requires a secure context (HTTPS, or localhost in dev). Browsers do
  // nothing — and show no prompt — when this isn't met, so explain it.
  if (!window.isSecureContext) {
    useAlert(msg.insecureContext);
    return;
  }
  if (!('Notification' in window)) {
    useAlert(msg.unsupported);
    return;
  }
  if (Notification.permission === 'granted') {
    registerSubscription(onSuccess, messages);
  } else if (Notification.permission === 'denied') {
    // The browser won't re-prompt once denied; the user must reset it manually.
    useAlert(msg.permissionDenied);
  } else {
    Notification.requestPermission().then(permission => {
      if (permission === 'granted') {
        registerSubscription(onSuccess, messages);
      } else if (permission === 'denied') {
        useAlert(msg.permissionDenied);
      }
    });
  }
};
