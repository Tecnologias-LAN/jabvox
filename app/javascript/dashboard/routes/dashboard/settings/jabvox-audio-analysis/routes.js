import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const AudioAnalysisSettings = () => import('./AudioAnalysisSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/audio-analysis'),
    name: 'jabvox_audio_analysis_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_AUDIO_ANALYSIS,
      permissions: ['administrator', 'agent'],
    },
    component: AudioAnalysisSettings,
  },
];
