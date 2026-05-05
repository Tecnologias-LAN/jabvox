import { frontendURL } from 'dashboard/helper/URLHelper.js';

const ManagementStatesSettings = () => import('./ManagementStatesSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/management-states'),
    name: 'jabvox_management_states_index',
    meta: {
      permissions: ['administrator'],
    },
    component: ManagementStatesSettings,
  },
];
