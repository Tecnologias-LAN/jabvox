import { frontendURL } from '../../../helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

import account from './account/account.routes';
import agent from './agents/agent.routes';
import assignmentPolicy from './assignmentPolicy/assignmentPolicy.routes';
import agentBot from './agentBots/agentBot.routes';
import attributes from './attributes/attributes.routes';
import automation from './automation/automation.routes';
import auditlogs from './auditlogs/audit.routes';
import billing from './billing/billing.routes';
import canned from './canned/canned.routes';
import inbox from './inbox/inbox.routes';
import integrations from './integrations/integrations.routes';
import labels from './labels/labels.routes';
import macros from './macros/macros.routes';
import reports from './reports/reports.routes';
import store from '../../../store';
import sla from './sla/sla.routes';
import teams from './teams/teams.routes';
import customRoles from './customRoles/customRole.routes';
import profile from './profile/profile.routes';
import security from './security/security.routes';
import conversationWorkflow from './conversationWorkflow/conversationWorkflow.routes';
import captain from './captain/captain.routes';
import { routes as jabvoxKanbanSettingsRoutes } from './jabvox-kanban/routes';
import { routes as jabvoxVoipRoutes } from './jabvox-voip/routes';
import { routes as jabvoxSaldoRoutes } from './jabvox-saldo/routes';
import { routes as jabvoxIpWhitelistRoutes } from './jabvox-ip-whitelist/routes';
import { routes as jabvoxAiChatSettingsRoutes } from './jabvox-ai-chat/routes';
import { routes as jabvoxManagementStatesRoutes } from './jabvox-management-states/routes';
import { routes as jabvoxDialerSettingsRoutes } from './jabvox-dialer/routes';
import { routes as jabvoxFieldSecurityRoutes } from './jabvox-field-security/routes';
import { routes as jabvoxAffiliatesRoutes } from './jabvox-affiliates/routes';
import { routes as jabvoxResponseBotRoutes } from './jabvox-response-bot/routes';
import { routes as jabvoxEmailSettingsRoutes } from './jabvox-email/routes';
import { routes as jabvoxFormsSettingsRoutes } from './jabvox-forms/routes';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings'),
      name: 'settings_home',
      meta: {
        permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      },
      redirect: to => {
        if (
          store.getters.getCurrentRole === 'administrator' &&
          store.getters.getCurrentCustomRoleId === null
        ) {
          return { name: 'general_settings_index', params: to.params };
        }

        return { name: 'canned_list', params: to.params };
      },
    },
    ...account.routes,
    ...agent.routes,
    ...assignmentPolicy.routes,
    ...agentBot.routes,
    ...attributes.routes,
    ...automation.routes,
    ...auditlogs.routes,
    ...billing.routes,
    ...canned.routes,
    ...inbox.routes,
    ...integrations.routes,
    ...labels.routes,
    ...macros.routes,
    ...reports.routes,
    ...sla.routes,
    ...teams.routes,
    ...customRoles.routes,
    ...profile.routes,
    ...security.routes,
    ...conversationWorkflow.routes,
    ...captain.routes,
    ...jabvoxFieldSecurityRoutes,
    ...jabvoxKanbanSettingsRoutes,
    ...jabvoxVoipRoutes,
    ...jabvoxSaldoRoutes,
    ...jabvoxIpWhitelistRoutes,
    ...jabvoxAiChatSettingsRoutes,
    ...jabvoxManagementStatesRoutes,
    ...jabvoxDialerSettingsRoutes,
    ...jabvoxAffiliatesRoutes,
    ...jabvoxResponseBotRoutes,
    ...jabvoxEmailSettingsRoutes,
    ...jabvoxFormsSettingsRoutes,
  ],
};
