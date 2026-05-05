import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const VoipSettings = () => import('./VoipSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/voip'),
    name: 'jabvox_voip_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_VOIP,
      permissions: ['administrator'],
    },
    component: VoipSettings,
  },
];
