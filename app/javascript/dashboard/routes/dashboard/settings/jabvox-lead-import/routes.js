import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const LeadImportSettings = () => import('./LeadImportSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/lead-import'),
    name: 'jabvox_lead_import_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_LEAD_IMPORT,
      permissions: ['administrator'],
    },
    component: LeadImportSettings,
  },
];
