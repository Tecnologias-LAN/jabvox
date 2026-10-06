import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper.js';

const IpWhitelistSettings = () => import('./IpWhitelistSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/ip-whitelist'),
    name: 'jabvox_ip_whitelist_index',
    featureFlag: FEATURE_FLAGS.JABVOX_IP_WHITELIST,
    meta: {
      permissions: ['administrator'],
    },
    component: IpWhitelistSettings,
  },
];
