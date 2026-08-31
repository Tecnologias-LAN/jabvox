import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const FlowsList = () => import('./FlowsList.vue');
const FlowEditor = () => import('./FlowEditor.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.JABVOX_ADVANCED_AUTOMATIONS,
  permissions: ['administrator'],
};

export const routes = [
  {
    path: frontendURL(
      'accounts/:accountId/settings/jabvox/advanced-automations'
    ),
    name: 'jabvox_advanced_automations_settings',
    meta,
    component: FlowsList,
  },
  {
    path: frontendURL(
      'accounts/:accountId/settings/jabvox/advanced-automations/:flowId'
    ),
    name: 'jabvox_advanced_automations_editor',
    meta,
    component: FlowEditor,
  },
];
