import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const DialerPage = () => import('./DialerPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/dialer'),
    name: 'jabvox_dialer_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_DIALER,
      permissions: ['administrator', 'agent'],
    },
    component: DialerPage,
  },
];
