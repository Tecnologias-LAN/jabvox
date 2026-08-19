import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const ProvisioningChat = () => import('./ProvisioningChat.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/provisioning-chat'),
    name: 'jabvox_provisioning_chat_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_AI_CHAT_PROVISIONING,
      permissions: ['administrator', 'agent'],
    },
    component: ProvisioningChat,
  },
];
