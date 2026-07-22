import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const CdrReportsPage = () => import('./CdrReportsPage.vue');
const CdrMonitorPage = () => import('./CdrMonitorPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/cdr-reports'),
    name: 'jabvox_cdr_reports_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_CDR,
      permissions: ['administrator', 'agent'],
    },
    component: CdrReportsPage,
  },
  {
    path: frontendURL('accounts/:accountId/jabvox/cdr-monitor'),
    name: 'jabvox_cdr_monitor',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_CDR,
      permissions: ['administrator'],
    },
    component: CdrMonitorPage,
  },
];
