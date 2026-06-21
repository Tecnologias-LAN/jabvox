import { frontendURL } from 'dashboard/helper/URLHelper.js';

const TypificationsSettings = () => import('./TypificationsSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/typifications'),
    name: 'jabvox_typifications_index',
    meta: {
      permissions: ['administrator'],
    },
    component: TypificationsSettings,
  },
];
