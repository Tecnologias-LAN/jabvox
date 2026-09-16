import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const WhatsappFlowsList = () => import('./WhatsappFlowsList.vue');
const WhatsappFlowBuilder = () => import('./WhatsappFlowBuilder.vue');

// "WhatsappFlow"/"whatsapp-flows" en toda la ruta — nunca "Flow" a secas
// (colisiona con el namespace de rutas `flows` de Automations).
export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/whatsapp-flows'),
    name: 'jabvox_whatsapp_flows_settings_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_WHATSAPP_FLOWS,
      permissions: ['administrator', 'agent'],
    },
    component: WhatsappFlowsList,
  },
  {
    path: frontendURL(
      'accounts/:accountId/settings/jabvox/whatsapp-flows/:flowId/builder'
    ),
    name: 'jabvox_whatsapp_flows_builder',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_WHATSAPP_FLOWS,
      permissions: ['administrator', 'agent'],
    },
    component: WhatsappFlowBuilder,
  },
];
