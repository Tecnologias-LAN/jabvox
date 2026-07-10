import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const JabvoxAffiliatesSettings = () => import('./JabvoxAffiliatesSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/affiliates'),
    name: 'jabvox_affiliates_index',
    meta: {
      permissions: ['administrator'],
      featureFlag: FEATURE_FLAGS.JABVOX_AFFILIATES,
    },
    component: JabvoxAffiliatesSettings,
  },
];
