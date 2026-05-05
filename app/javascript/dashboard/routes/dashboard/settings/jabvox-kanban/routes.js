import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const FunnelList = () => import('./FunnelList.vue');
const FunnelForm = () => import('./FunnelForm.vue');
const StageSettings = () => import('./StageSettings.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.JABVOX_KANBAN,
  permissions: ['administrator'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/kanban/funnels'),
    name: 'jabvox_kanban_funnels_index',
    meta,
    component: FunnelList,
  },
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/kanban/funnels/new'),
    name: 'jabvox_kanban_funnels_new',
    meta,
    component: FunnelForm,
  },
  {
    path: frontendURL(
      'accounts/:accountId/settings/jabvox/kanban/funnels/:funnelId/edit'
    ),
    name: 'jabvox_kanban_funnels_edit',
    meta,
    component: FunnelForm,
  },
  {
    path: frontendURL(
      'accounts/:accountId/settings/jabvox/kanban/funnels/:funnelId/stages'
    ),
    name: 'jabvox_kanban_stages',
    meta,
    component: StageSettings,
  },
];
