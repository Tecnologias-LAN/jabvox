import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const JabvoxReportsPage = () => import('./JabvoxReportsPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/reports'),
    name: 'jabvox_reports_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_PRODUCTS,
      permissions: ['administrator', 'agent'],
    },
    component: JabvoxReportsPage,
  },
];
