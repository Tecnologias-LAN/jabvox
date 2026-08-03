import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const VoiceBroadcastSettings = () => import('./VoiceBroadcastSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/voice-broadcast'),
    name: 'jabvox_voice_broadcast_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_VOICE_BROADCAST,
      // Admins always; custom roles enter with the manage grant (backend enforces
      // jabvox_voice_broadcast_manage OR jabvox_dialer_manage in the controller).
      permissions: ['administrator', 'jabvox_voice_broadcast_manage'],
    },
    component: VoiceBroadcastSettings,
  },
];
