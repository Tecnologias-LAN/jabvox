import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const AiChat = () => import('./AiChat.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/ai-chat'),
    name: 'jabvox_ai_chat_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_AI_CHAT,
      permissions: ['administrator', 'agent'],
    },
    component: AiChat,
  },
];
