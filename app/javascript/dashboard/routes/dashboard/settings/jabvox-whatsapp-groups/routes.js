import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const WhatsappGroupsSettings = () => import('./WhatsappGroupsSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/whatsapp-groups'),
    name: 'jabvox_whatsapp_groups_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_WHATSAPP_GROUPS,
      // Admins always; custom roles enter with the manage grant (backend enforces
      // the same key in WhatsappGroups::BaseController#ensure_admin).
      permissions: ['administrator', 'jabvox_whatsapp_groups_manage'],
    },
    component: WhatsappGroupsSettings,
  },
];
