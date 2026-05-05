import { frontendURL } from 'dashboard/helper/URLHelper.js';

const IpWhitelistSettings = () => import('./IpWhitelistSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/ip-whitelist'),
    name: 'jabvox_ip_whitelist_index',
    meta: {
      permissions: ['administrator'],
    },
    component: IpWhitelistSettings,
  },
];
