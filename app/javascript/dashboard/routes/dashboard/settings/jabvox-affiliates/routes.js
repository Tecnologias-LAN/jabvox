import { frontendURL } from 'dashboard/helper/URLHelper.js';

const JabvoxAffiliatesSettings = () => import('./JabvoxAffiliatesSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/affiliates'),
    name: 'jabvox_affiliates_index',
    meta: {
      permissions: ['administrator'],
    },
    component: JabvoxAffiliatesSettings,
  },
];
