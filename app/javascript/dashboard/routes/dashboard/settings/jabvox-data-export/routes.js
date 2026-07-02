import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const DataExportSettings = () => import('./DataExportSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/data-export'),
    name: 'jabvox_data_export_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_DATA_EXPORT,
      permissions: ['administrator'],
    },
    component: DataExportSettings,
  },
];
