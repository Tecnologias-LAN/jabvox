import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const CalendarView = () => import('./CalendarView.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/calendar'),
    name: 'jabvox_calendar_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_CALENDAR,
      permissions: ['administrator', 'agent'],
    },
    component: CalendarView,
  },
];
