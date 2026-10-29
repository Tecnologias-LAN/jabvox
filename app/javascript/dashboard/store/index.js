import { createStore } from 'vuex';

import accounts from './modules/accounts';
import agentBots from './modules/agentBots';
import agentCapacityPolicies from './modules/agentCapacityPolicies';
import agents from './modules/agents';
import assignmentPolicies from './modules/assignmentPolicies';
import articles from './modules/helpCenterArticles';
import attributes from './modules/attributes';
import auditlogs from './modules/auditlogs';
import auth from './modules/auth';
import automations from './modules/automations';
import bulkActions from './modules/bulkActions';
import campaigns from './modules/campaigns';
import cannedResponse from './modules/cannedResponse';
import categories from './modules/helpCenterCategories';
import contactConversations from './modules/contactConversations';
import contactLabels from './modules/contactLabels';
import contactNotes from './modules/contactNotes';
import contacts from './modules/contacts';
import conversationLabels from './modules/conversationLabels';
import conversationMetadata from './modules/conversationMetadata';
import conversationPage from './modules/conversationPage';
import conversations from './modules/conversations';
import conversationSearch from './modules/conversationSearch';
import conversationStats from './modules/conversationStats';
import conversationTypingStatus from './modules/conversationTypingStatus';
import conversationUnreadCounts from './modules/conversationUnreadCounts';
import conversationWatchers from './modules/conversationWatchers';
import csat from './modules/csat';
import customRole from './modules/customRole';
import customViews from './modules/customViews';
import dashboardApps from './modules/dashboardApps';
import draftMessages from './modules/draftMessages';
import globalConfig from 'shared/store/globalConfig';
import inboxAssignableAgents from './modules/inboxAssignableAgents';
import inboxes from './modules/inboxes';
import inboxMembers from './modules/inboxMembers';
import integrations from './modules/integrations';
import labels from './modules/labels';
import macros from './modules/macros';
import notifications from './modules/notifications';
import portals from './modules/helpCenterPortals';
import reports from './modules/reports';
import sla from './modules/sla';
import slaReports from './modules/SLAReports';
import sidebarSortPreferences from './modules/sidebarSortPreferences';
import summaryReports from './modules/summaryReports';
import teamMembers from './modules/teamMembers';
import teams from './modules/teams';
import userNotificationSettings from './modules/userNotificationSettings';
import webhooks from './modules/webhooks';
import jabvoxKanban from './modules/jabvox/kanban';
import jabvoxProducts from './modules/jabvox/products';
import jabvoxVoip from './modules/jabvox/voip';
import jabvoxSaldo from './modules/jabvox/saldo';
import jabvoxSms from './modules/jabvox/sms';
import jabvoxIpWhitelist from './modules/jabvox/ipWhitelist';
import jabvoxAiChat from './modules/jabvox/aiChat';
import jabvoxManagementStates from './modules/jabvox/managementStates';
import jabvoxDialer from './modules/jabvox/dialer';
import jabvoxOrders from './modules/jabvox/orders';
import jabvoxReportsAnalytics from './modules/jabvox/reportsAnalytics';
import jabvoxFieldVisibilities from './modules/jabvox/fieldVisibilities';
import jabvoxTickets from './modules/jabvox/tickets';
import jabvoxAffiliates from './modules/jabvox/affiliates';
import jabvoxCalendar from './modules/jabvox/calendar';
import jabvoxInternalChat from './modules/jabvox/internalChat';
import jabvoxAppStates from './modules/jabvox/appStates';
import jabvoxCampaigns from './modules/jabvox/campaigns';
import jabvoxEmail from './modules/jabvox/email';
import jabvoxForms from './modules/jabvox/forms';
import jabvoxCustomization from './modules/jabvox/customization';
import jabvoxDrive from './modules/jabvox/drive';

const plugins = [];

export default createStore({
  modules: {
    accounts,
    agentBots,
    agentCapacityPolicies,
    agents,
    assignmentPolicies,
    articles,
    attributes,
    auditlogs,
    auth,
    automations,
    bulkActions,
    campaigns,
    cannedResponse,
    categories,
    contactConversations,
    contactLabels,
    contactNotes,
    contacts,
    conversationLabels,
    conversationMetadata,
    conversationPage,
    conversations,
    conversationSearch,
    conversationStats,
    conversationTypingStatus,
    conversationUnreadCounts,
    conversationWatchers,
    csat,
    customRole,
    customViews,
    dashboardApps,
    draftMessages,
    globalConfig,
    inboxAssignableAgents,
    inboxes,
    inboxMembers,
    integrations,
    labels,
    macros,
    notifications,
    portals,
    reports,
    sla,
    slaReports,
    sidebarSortPreferences,
    summaryReports,
    teamMembers,
    teams,
    userNotificationSettings,
    webhooks,
    jabvoxKanban,
    jabvoxProducts,
    jabvoxVoip,
    jabvoxSaldo,
    jabvoxSms,
    jabvoxIpWhitelist,
    jabvoxAiChat,
    jabvoxManagementStates,
    jabvoxDialer,
    jabvoxOrders,
    jabvoxReportsAnalytics,
    jabvoxFieldVisibilities,
    jabvoxTickets,
    jabvoxAffiliates,
    jabvoxCalendar,
    jabvoxInternalChat,
    jabvoxAppStates,
    jabvoxCampaigns,
    jabvoxEmail,
    jabvoxForms,
    jabvoxCustomization,
    jabvoxDrive,
  },
  plugins,
});
