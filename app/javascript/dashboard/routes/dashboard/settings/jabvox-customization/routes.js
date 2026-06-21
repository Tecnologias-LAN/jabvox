import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const CustomizationSettings = () => import('./CustomizationSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/customization'),
    name: 'jabvox_customization_settings',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_CUSTOMIZATION,
      permissions: ['administrator'],
    },
    component: CustomizationSettings,
  },
];
