import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const CustomDataView = () => import('./CustomDataView.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/custom-data'),
    name: 'jabvox_custom_data_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_CUSTOMIZATION,
      permissions: ['administrator', 'jabvox_custom_data_manage'],
    },
    component: CustomDataView,
  },
];
