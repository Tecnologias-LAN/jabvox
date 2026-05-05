import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const DialerSettings = () => import('./DialerSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/dialer'),
    name: 'jabvox_dialer_settings',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_DIALER,
      permissions: ['administrator'],
    },
    component: DialerSettings,
  },
];
