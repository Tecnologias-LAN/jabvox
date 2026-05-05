import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const InternalChatPage = () => import('./InternalChatPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/internal-chat'),
    name: 'jabvox_internal_chat_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_INTERNAL_CHAT,
      permissions: ['administrator', 'agent'],
    },
    component: InternalChatPage,
  },
];
