import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const CdrSettings = () => import('./CdrSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/cdr'),
    name: 'jabvox_cdr_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_CDR,
      permissions: ['administrator'],
    },
    component: CdrSettings,
  },
];
