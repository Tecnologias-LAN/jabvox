import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const JabvoxEmailIndex = () => import('./JabvoxEmailIndex.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/email'),
    name: 'jabvox_email_settings',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_EMAIL,
      permissions: ['administrator'],
    },
    component: JabvoxEmailIndex,
  },
];
