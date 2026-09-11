import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const AiBudgetSettings = () => import('./AiBudgetSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/ai-budget'),
    name: 'jabvox_ai_budget_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_AI_CHAT,
      permissions: ['administrator'],
    },
    component: AiBudgetSettings,
  },
];
