import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const AiChatSettings = () => import('./AiChatSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/ai-chat'),
    name: 'jabvox_ai_chat_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_AI_CHAT,
      permissions: ['administrator'],
    },
    component: AiChatSettings,
  },
];
