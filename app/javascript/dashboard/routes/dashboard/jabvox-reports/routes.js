import { frontendURL } from 'dashboard/helper/URLHelper.js';

const JabvoxReportsPage = () => import('./JabvoxReportsPage.vue');
const JabvoxReportDrilldownPage = () =>
  import('./JabvoxReportDrilldownPage.vue');

const permissions = ['administrator', 'jabvox_reports_view'];

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/reports'),
    name: 'jabvox_reports_index',
    meta: {
      // Admins always pass; other users need the custom-role permission.
      // Direct URL access is blocked by the router guard for anyone else,
      // and the API is gated server-side by the same permission.
      permissions,
    },
    component: JabvoxReportsPage,
  },
  {
    // Metric drill-down at its own shareable URL. `metricKey` selects the
    // metric; range/filters/order/page live in the query string.
    path: frontendURL('accounts/:accountId/jabvox/reports/:metricKey'),
    name: 'jabvox_reports_drilldown',
    meta: { permissions },
    component: JabvoxReportDrilldownPage,
  },
];
