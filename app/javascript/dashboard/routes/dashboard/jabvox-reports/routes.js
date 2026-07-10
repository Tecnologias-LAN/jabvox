import { frontendURL } from 'dashboard/helper/URLHelper.js';

const JabvoxReportsPage = () => import('./JabvoxReportsPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/reports'),
    name: 'jabvox_reports_index',
    meta: {
      // Admins always pass; other users need the custom-role permission.
      // Direct URL access is blocked by the router guard for anyone else,
      // and the API is gated server-side by the same permission.
      permissions: ['administrator', 'jabvox_reports_view'],
    },
    component: JabvoxReportsPage,
  },
];
