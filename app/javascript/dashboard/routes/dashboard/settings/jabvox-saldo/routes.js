import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const SaldoSettings = () => import('./SaldoSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/saldo'),
    name: 'jabvox_saldo_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_SALDO,
      permissions: ['administrator'],
    },
    component: SaldoSettings,
  },
];
