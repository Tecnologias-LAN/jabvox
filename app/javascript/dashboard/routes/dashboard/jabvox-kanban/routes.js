import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const KanbanView = () => import('./KanbanView.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.JABVOX_KANBAN,
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/kanban'),
    name: 'jabvox_kanban_index',
    meta,
    component: KanbanView,
  },
  {
    path: frontendURL('accounts/:accountId/jabvox/kanban/:funnelId'),
    name: 'jabvox_kanban_funnel',
    meta,
    component: KanbanView,
  },
];
