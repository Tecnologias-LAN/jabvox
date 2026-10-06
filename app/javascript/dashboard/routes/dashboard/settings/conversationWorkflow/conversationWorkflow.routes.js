import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import ConversationWorkflowIndex from './index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/conversation-workflow'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'conversation_workflow_index',
          component: ConversationWorkflowIndex,
          meta: {
            featureFlag: FEATURE_FLAGS.JABVOX_CONVERSATION_WORKFLOW,
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
