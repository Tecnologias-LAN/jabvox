import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const JabvoxSmsIndex = () => import('./JabvoxSmsIndex.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/sms'),
    name: 'jabvox_sms_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_SMS,
      permissions: ['administrator'],
    },
    component: JabvoxSmsIndex,
  },
];
