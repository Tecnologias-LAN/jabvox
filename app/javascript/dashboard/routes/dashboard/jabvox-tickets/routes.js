import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const TicketsLayout = () => import('./TicketsLayout.vue');
const TicketsIndex = () => import('./TicketsIndex.vue');
const TicketDetail = () => import('./TicketDetail.vue');
const TicketMetrics = () => import('./TicketMetrics.vue');
const TicketCategoriesAdmin = () => import('./TicketCategoriesAdmin.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.JABVOX_TICKETS,
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/tickets'),
    component: TicketsLayout,
    children: [
      {
        path: '',
        name: 'jabvox_tickets_index',
        meta,
        component: TicketsIndex,
      },
      {
        path: 'metrics',
        name: 'jabvox_tickets_metrics',
        meta,
        component: TicketMetrics,
      },
      {
        path: 'categorias',
        name: 'jabvox_tickets_categories',
        meta,
        component: TicketCategoriesAdmin,
      },
      {
        path: ':ticketId',
        name: 'jabvox_tickets_detail',
        meta,
        component: TicketDetail,
      },
    ],
  },
];
