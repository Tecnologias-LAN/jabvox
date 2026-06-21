import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const AudioAnalysisReportsPage = () => import('./AudioAnalysisReportsPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/audio-analysis-reports'),
    name: 'jabvox_audio_analysis_reports_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_AUDIO_ANALYSIS,
      permissions: ['administrator', 'agent'],
    },
    component: AudioAnalysisReportsPage,
  },
];
