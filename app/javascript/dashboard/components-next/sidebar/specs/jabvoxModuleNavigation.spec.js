import { createJabvoxModuleNavigation } from '../jabvoxModuleNavigation';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const enabledFeatures = new Set([
  FEATURE_FLAGS.MENTIONS,
  FEATURE_FLAGS.LABELS,
  FEATURE_FLAGS.PARTICIPATING,
  FEATURE_FLAGS.UNATTENDED,
  FEATURE_FLAGS.TEAM_MANAGEMENT,
  FEATURE_FLAGS.REPORTS,
  FEATURE_FLAGS.JABVOX_BULK_WHATSAPP,
  FEATURE_FLAGS.JABVOX_KANBAN,
  FEATURE_FLAGS.JABVOX_CALENDAR,
  FEATURE_FLAGS.JABVOX_TASKS,
  FEATURE_FLAGS.JABVOX_INTERNAL_CHAT,
  FEATURE_FLAGS.JABVOX_TICKETS,
  FEATURE_FLAGS.JABVOX_CUSTOMIZATION,
  FEATURE_FLAGS.JABVOX_AI_CHAT,
  FEATURE_FLAGS.JABVOX_AI_CHAT_PROVISIONING,
  FEATURE_FLAGS.JABVOX_DIALER,
  FEATURE_FLAGS.JABVOX_AUDIO_ANALYSIS,
  FEATURE_FLAGS.JABVOX_CDR,
  FEATURE_FLAGS.JABVOX_ANALYTICS,
]);

const buildGroups = ({ deniedRoutes = [] } = {}) =>
  createJabvoxModuleNavigation({
    t: key => key,
    accountScopedRoute: name => ({ name }),
    hasFeature: flag => enabledFeatures.has(flag),
    isRouteAllowed: to => !deniedRoutes.includes(to.name),
    isCallsAvailable: true,
    canViewJabvoxReports: true,
  });

describe('Jabvox module navigation', () => {
  it('groups the requested modules under their matching section', () => {
    const groups = buildGroups();
    const tabsFor = groupName =>
      groups
        .find(group => group.name === groupName)
        .tabs.map(tab => tab.to?.name);
    const conversations = groups.find(group => group.name === 'Conversations');

    expect(conversations.tabs.map(tab => tab.key)).toEqual([
      'all-conversations',
      'labels',
      'channels',
      'mentions',
      'participating',
      'unattended',
      'folders',
      'teams',
      'contacts',
    ]);
    expect(conversations.tabs.find(tab => tab.key === 'channels').label).toBe(
      'SIDEBAR.CONVERSATION_INBOXES'
    );

    expect(tabsFor('Management')).toEqual([
      'jabvox_kanban_index',
      'jabvox_calendar_index',
      'jabvox_tasks_index',
      'jabvox_internal_chat_index',
      'jabvox_tickets_index',
      'jabvox_custom_data_index',
    ]);
    expect(tabsFor('Jabvox AI')).toEqual([
      'jabvox_ai_chat_index',
      'jabvox_provisioning_chat_index',
    ]);
    const reports = groups.find(group => group.name === 'Reports');
    const reportsMenu = reports.tabs.find(
      tab => tab.key === 'reports-overview'
    );

    expect(reports.tabs.map(tab => tab.to?.name)).toEqual([
      'jabvox_reports_index',
      'calls_dashboard_index',
      'jabvox_audio_analysis_reports_index',
      'jabvox_cdr_reports_index',
      'account_overview_reports',
    ]);
    expect(reportsMenu.kind).toBeUndefined();
    expect(reportsMenu.subTabs.map(item => item.to.name)).toEqual([
      'account_overview_reports',
      'agent_reports_index',
      'label_reports_index',
      'inbox_reports_index',
      'team_reports_index',
      'whatsapp_templates_reports',
    ]);
    expect(reportsMenu.activeOn).toContain('whatsapp_templates_reports');
    expect(tabsFor('Analytics BI')).toEqual(['jabvox_analytics_index']);
    expect(tabsFor('Dialer')).toEqual(['jabvox_dialer_index']);
  });

  it('falls back to the first allowed destination and hides unavailable groups', () => {
    const groups = buildGroups({
      deniedRoutes: ['jabvox_kanban_index', 'jabvox_calendar_index'],
    });
    const management = groups.find(group => group.name === 'Management');

    expect(management.to.name).toBe('jabvox_tasks_index');
    expect(management.tabs.map(tab => tab.to?.name)).not.toContain(
      'jabvox_kanban_index'
    );

    const noEnabledFeatures = createJabvoxModuleNavigation({
      t: key => key,
      accountScopedRoute: name => ({ name }),
      hasFeature: () => false,
      isRouteAllowed: () => true,
      isCallsAvailable: false,
      canViewJabvoxReports: false,
    });

    expect(noEnabledFeatures.map(group => group.name)).toEqual([
      'Conversations',
      'Reports',
    ]);
  });

  it('hides conversation menus when no route is allowed for the role', () => {
    const groups = buildGroups({
      deniedRoutes: [
        'inbox_dashboard',
        'inbox_view',
        'label_conversations',
        'folder_conversations',
        'team_conversations',
      ],
    });
    const conversations = groups.find(group => group.name === 'Conversations');

    expect(conversations.tabs.map(tab => tab.key)).not.toEqual(
      expect.arrayContaining(['channels', 'labels', 'folders', 'teams'])
    );
  });

  it('keeps permitted inbox and label tabs visible when their lists are empty', () => {
    const groups = buildGroups();
    const conversations = groups.find(group => group.name === 'Conversations');

    expect(conversations.tabs.map(tab => tab.key)).toEqual(
      expect.arrayContaining(['labels', 'channels'])
    );
  });
});
