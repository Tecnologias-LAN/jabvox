import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper.js';

const ManagementStatesSettings = () => import('./ManagementStatesSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/management-states'),
    name: 'jabvox_management_states_index',
    featureFlag: FEATURE_FLAGS.JABVOX_MANAGEMENT_STATES,
    meta: {
      permissions: ['administrator'],
    },
    component: ManagementStatesSettings,
  },
];
