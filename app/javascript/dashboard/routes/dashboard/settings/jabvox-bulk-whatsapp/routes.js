import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const BulkWhatsappSettings = () => import('./BulkWhatsappSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/bulk-whatsapp'),
    name: 'jabvox_bulk_whatsapp_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_BULK_WHATSAPP,
      // Admins always; custom roles enter with the send grant (backend enforces
      // the same key in BulkWhatsapp::BaseController#ensure_admin).
      permissions: ['administrator', 'jabvox_bulk_whatsapp_send'],
    },
    component: BulkWhatsappSettings,
  },
];
