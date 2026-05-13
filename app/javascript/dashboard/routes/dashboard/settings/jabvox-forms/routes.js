import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const JabvoxFormIndex = () => import('./JabvoxFormIndex.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/forms'),
    name: 'jabvox_forms_settings',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_FORMS,
      permissions: ['administrator'],
    },
    component: JabvoxFormIndex,
  },
];
