import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const AdvancedAutomations = () => import('./AdvancedAutomations.vue');

export const routes = [
  {
    path: frontendURL(
      'accounts/:accountId/settings/jabvox/advanced-automations'
    ),
    name: 'jabvox_advanced_automations_settings',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_ADVANCED_AUTOMATIONS,
      permissions: ['administrator'],
    },
    component: AdvancedAutomations,
  },
];
