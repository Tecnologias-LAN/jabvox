import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const WhatsappTemplatesSettings = () => import('./WhatsappTemplatesSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/whatsapp-templates'),
    name: 'jabvox_whatsapp_templates_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_WHATSAPP_TEMPLATES,
      permissions: ['administrator', 'agent'],
    },
    component: WhatsappTemplatesSettings,
  },
];
