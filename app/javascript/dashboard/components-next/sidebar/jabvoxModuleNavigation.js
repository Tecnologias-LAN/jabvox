import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const routeTab = (
  key,
  label,
  routeName,
  accountScopedRoute,
  activeOn = [],
  extra = {}
) => ({
  key,
  label,
  to: accountScopedRoute(routeName),
  activeOn: [routeName, ...activeOn],
  ...extra,
});

const menuTab = (key, label, routeNames, permissionRoutes, items = []) => ({
  key,
  label,
  kind: 'menu',
  routeNames,
  permissionRoutes,
  items,
});

const makeGroup = (name, label, icon, tabs, isRouteAllowed) => {
  const visibleTabs = tabs.filter(tab =>
    tab.kind === 'menu'
      ? tab.permissionRoutes.some(isRouteAllowed)
      : isRouteAllowed(tab.to)
  );
  const defaultTab = visibleTabs.find(tab => tab.to);

  if (!defaultTab) return null;

  return {
    name,
    label,
    icon,
    tabs: visibleTabs,
    to: defaultTab.to,
    getterKeys: visibleTabs.find(tab => tab.getterKeys)?.getterKeys,
    activeOn: visibleTabs.flatMap(tab => [
      ...(tab.activeOn || []),
      ...(tab.routeNames || []),
      ...(tab.subTabs || []).flatMap(subTab => subTab.activeOn || []),
    ]),
  };
};

export const createJabvoxModuleNavigation = ({
  t,
  accountScopedRoute,
  hasFeature,
  isRouteAllowed,
  isCallsAvailable,
  canViewJabvoxReports,
}) => {
  const conversations = [
    routeTab(
      'all-conversations',
      t('SIDEBAR.ALL_CONVERSATIONS'),
      'home',
      accountScopedRoute,
      ['inbox_conversation'],
      {
        badgeKey: 'all',
        getterKeys: { count: 'conversationUnreadCounts/getAllUnreadCount' },
      }
    ),
    ...(hasFeature(FEATURE_FLAGS.LABELS)
      ? [
          menuTab(
            'labels',
            t('SIDEBAR.LABELS'),
            ['label_conversations', 'conversations_through_label'],
            [
              accountScopedRoute('label_conversations', {
                label: 'permission-check',
              }),
            ]
          ),
        ]
      : []),
    // Empresas vive dentro de Conversaciones, junto a Contactos: una empresa agrupa
    // contactos, y desde ahí se llega a sus conversaciones. Como sección suelta de
    // primer nivel quedaba desconectada de lo que agrupa.
    ...(hasFeature(FEATURE_FLAGS.COMPANIES)
      ? [
          routeTab(
            'companies',
            t('SIDEBAR.COMPANIES'),
            'companies_dashboard_index',
            accountScopedRoute,
            ['companies_dashboard_show']
          ),
        ]
      : []),
    menuTab(
      'channels',
      t('SIDEBAR.CONVERSATION_INBOXES'),
      [
        'inbox_dashboard',
        'conversation_through_inbox',
        'inbox_view',
        'inbox_view_conversation',
      ],
      [
        accountScopedRoute('inbox_dashboard', { inbox_id: 1 }),
        accountScopedRoute('inbox_view'),
      ]
    ),
  ];

  if (hasFeature(FEATURE_FLAGS.MENTIONS)) {
    conversations.push(
      routeTab(
        'mentions',
        t('SIDEBAR.MENTIONED_CONVERSATIONS'),
        'conversation_mentions',
        accountScopedRoute,
        ['conversation_through_mentions'],
        { badgeKey: 'mentions' }
      )
    );
  }

  if (hasFeature(FEATURE_FLAGS.PARTICIPATING)) {
    conversations.push(
      routeTab(
        'participating',
        t('SIDEBAR.PARTICIPATING_CONVERSATIONS'),
        'conversation_participating',
        accountScopedRoute,
        ['conversation_through_participating'],
        { badgeKey: 'participating' }
      )
    );
  }

  if (hasFeature(FEATURE_FLAGS.UNATTENDED)) {
    conversations.push(
      routeTab(
        'unattended',
        t('SIDEBAR.UNATTENDED_CONVERSATIONS'),
        'conversation_unattended',
        accountScopedRoute,
        ['conversation_through_unattended'],
        { badgeKey: 'unattended' }
      )
    );
  }

  conversations.push(
    menuTab(
      'folders',
      t('SIDEBAR.CUSTOM_VIEWS_FOLDER'),
      ['folder_conversations', 'conversations_through_folders'],
      [accountScopedRoute('folder_conversations', { id: 1 })]
    ),
    ...(hasFeature(FEATURE_FLAGS.TEAM_MANAGEMENT)
      ? [
          menuTab(
            'teams',
            t('SIDEBAR.TEAMS'),
            ['team_conversations', 'conversations_through_team'],
            [accountScopedRoute('team_conversations', { teamId: 1 })]
          ),
        ]
      : [])
  );

  conversations.push({
    key: 'contacts',
    label: t('SIDEBAR.CONTACTS'),
    to: accountScopedRoute(
      'contacts_dashboard_index',
      {},
      { page: 1, search: undefined }
    ),
    activeOn: [
      'contacts_dashboard_index',
      'contacts_edit',
      'contacts_dashboard_active',
      'contacts_dashboard_segments_index',
      'contacts_edit_segment',
      'contacts_dashboard_labels_index',
      'contacts_edit_label',
    ],
  });

  const management = [
    ...(hasFeature(FEATURE_FLAGS.JABVOX_KANBAN)
      ? [
          routeTab(
            'kanban',
            t('SIDEBAR.JABVOX_KANBAN'),
            'jabvox_kanban_index',
            accountScopedRoute,
            ['jabvox_kanban_funnel']
          ),
        ]
      : []),
    ...(hasFeature(FEATURE_FLAGS.JABVOX_CALENDAR)
      ? [
          routeTab(
            'calendar',
            t('JABVOX_CALENDAR.SIDEBAR_LABEL'),
            'jabvox_calendar_index',
            accountScopedRoute
          ),
        ]
      : []),
    ...(hasFeature(FEATURE_FLAGS.JABVOX_TASKS)
      ? [
          routeTab(
            'tasks',
            t('SIDEBAR.JABVOX_TASKS'),
            'jabvox_tasks_index',
            accountScopedRoute,
            ['jabvox_tasks_board', 'jabvox_tasks_detail']
          ),
        ]
      : []),
    ...(hasFeature(FEATURE_FLAGS.JABVOX_INTERNAL_CHAT)
      ? [
          routeTab(
            'internal-chat',
            t('JABVOX_INTERNAL_CHAT.SIDEBAR_LABEL'),
            'jabvox_internal_chat_index',
            accountScopedRoute,
            [],
            { getterKeys: { count: 'jabvoxInternalChat/getUnreadTotal' } }
          ),
        ]
      : []),
    ...(hasFeature(FEATURE_FLAGS.JABVOX_TICKETS)
      ? [
          routeTab(
            'tickets',
            t('SIDEBAR.JABVOX_TICKETS'),
            'jabvox_tickets_index',
            accountScopedRoute,
            [
              'jabvox_tickets_detail',
              'jabvox_tickets_metrics',
              'jabvox_tickets_categories',
            ]
          ),
        ]
      : []),
    ...(hasFeature(FEATURE_FLAGS.JABVOX_CUSTOMIZATION)
      ? [
          routeTab(
            'custom-data',
            t('SIDEBAR.JABVOX_CUSTOM_DATA'),
            'jabvox_custom_data_index',
            accountScopedRoute
          ),
        ]
      : []),
    ...(hasFeature(FEATURE_FLAGS.JABVOX_DRIVE)
      ? [
          routeTab(
            'jabvox-drive',
            t('SIDEBAR.JABVOX_DRIVE'),
            'jabvox_drive_index',
            accountScopedRoute,
            [
              'jabvox_drive_folder',
              'jabvox_drive_contact',
              'jabvox_drive_history',
              'jabvox_drive_trash',
            ]
          ),
        ]
      : []),
  ];

  const ai = [
    ...(hasFeature(FEATURE_FLAGS.JABVOX_AI_CHAT)
      ? [
          routeTab(
            'ai-chat',
            t('JABVOX_AI_CHAT.SIDEBAR_LABEL'),
            'jabvox_ai_chat_index',
            accountScopedRoute
          ),
        ]
      : []),
    ...(hasFeature(FEATURE_FLAGS.JABVOX_AI_CHAT_PROVISIONING)
      ? [
          routeTab(
            'provisioning-chat',
            t('JABVOX_PROVISIONING_CHAT.SIDEBAR_LABEL'),
            'jabvox_provisioning_chat_index',
            accountScopedRoute
          ),
        ]
      : []),
  ];

  const reports = [
    routeTab(
      'jabvox-reports',
      t('JABVOX_REPORTS.SIDEBAR_LABEL'),
      'jabvox_reports_index',
      accountScopedRoute,
      ['jabvox_reports_drilldown']
    ),
    ...(isCallsAvailable
      ? [
          routeTab(
            'calls',
            t('SIDEBAR.CALLS'),
            'calls_dashboard_index',
            accountScopedRoute
          ),
        ]
      : []),
    ...(canViewJabvoxReports && hasFeature(FEATURE_FLAGS.JABVOX_AUDIO_ANALYSIS)
      ? [
          routeTab(
            'audio-reports',
            t('JABVOX_AUDIO.SIDEBAR_LABEL'),
            'jabvox_audio_analysis_reports_index',
            accountScopedRoute
          ),
        ]
      : []),
    ...(canViewJabvoxReports && hasFeature(FEATURE_FLAGS.JABVOX_CDR)
      ? [
          routeTab(
            'cdr-reports',
            t('JABVOX_CDR.SIDEBAR_LABEL'),
            'jabvox_cdr_reports_index',
            accountScopedRoute
          ),
        ]
      : []),
  ];

  const reportsOverviewItems = [
    ...(hasFeature(FEATURE_FLAGS.REPORTS)
      ? [
          routeTab(
            'reports-overview',
            t('SIDEBAR.REPORTS_OVERVIEW'),
            'account_overview_reports',
            accountScopedRoute
          ),
          routeTab(
            'agents-report',
            t('SIDEBAR.REPORTS_AGENT'),
            'agent_reports_index',
            accountScopedRoute,
            ['agent_reports_show']
          ),
          routeTab(
            'labels-report',
            t('SIDEBAR.REPORTS_LABEL'),
            'label_reports_index',
            accountScopedRoute,
            ['label_reports_show']
          ),
          routeTab(
            'inbox-report',
            t('SIDEBAR.REPORTS_INBOX'),
            'inbox_reports_index',
            accountScopedRoute,
            ['inbox_reports_show']
          ),
          routeTab(
            'team-report',
            t('SIDEBAR.REPORTS_TEAM'),
            'team_reports_index',
            accountScopedRoute,
            ['team_reports_show']
          ),
        ]
      : []),
    ...(hasFeature(FEATURE_FLAGS.JABVOX_BULK_WHATSAPP)
      ? [
          routeTab(
            'whatsapp-template-report',
            t('SIDEBAR.REPORTS_WHATSAPP_TEMPLATES'),
            'whatsapp_templates_reports',
            accountScopedRoute
          ),
        ]
      : []),
  ];
  const reportsOverviewActiveOn = reportsOverviewItems.flatMap(tab => [
    ...(tab.activeOn || []),
  ]);
  const reportsOverviewTab = routeTab(
    'reports-overview',
    t('SIDEBAR.JABVOX_REPORTS_MENU'),
    'account_overview_reports',
    accountScopedRoute,
    reportsOverviewActiveOn,
    { subTabs: reportsOverviewItems }
  );
  const analyticsBi = hasFeature(FEATURE_FLAGS.JABVOX_ANALYTICS)
    ? [
        routeTab(
          'analytics-bi',
          t('SIDEBAR.JABVOX_ANALYTICS_BI'),
          'jabvox_analytics_index',
          accountScopedRoute,
          [
            'jabvox_analytics_overview',
            'jabvox_analytics_data_sources',
            'jabvox_analytics_ds_tables',
            'jabvox_analytics_ds_viewer',
            'jabvox_analytics_query_builder',
            'jabvox_analytics_sql',
            'jabvox_analytics_dashboards',
            'jabvox_analytics_dashboard_show',
            'jabvox_analytics_cross_reports',
            'jabvox_analytics_cross_report_new',
            'jabvox_analytics_cross_report_edit',
            'jabvox_analytics_permissions',
          ]
        ),
      ]
    : [];
  const groups = [
    makeGroup(
      'Conversations',
      t('SIDEBAR.CONVERSATIONS'),
      'i-lucide-message-circle',
      conversations,
      isRouteAllowed
    ),
    makeGroup(
      'Management',
      t('SIDEBAR.JABVOX_MANAGEMENT'),
      'i-lucide-layout-grid',
      management,
      isRouteAllowed
    ),
    makeGroup(
      'Jabvox AI',
      t('SIDEBAR.JABVOX_AI'),
      'i-ri-robot-2-line',
      ai,
      isRouteAllowed
    ),
    makeGroup(
      'Reports',
      t('SIDEBAR.JABVOX_REPORTS_GROUP'),
      'i-lucide-chart-spline',
      [...reports, reportsOverviewTab],
      isRouteAllowed
    ),
    makeGroup(
      'Analytics BI',
      t('SIDEBAR.JABVOX_ANALYTICS_BI'),
      'i-lucide-chart-no-axes-combined',
      analyticsBi,
      isRouteAllowed
    ),
    makeGroup(
      'Dialer',
      t('SIDEBAR.CALLS'),
      'i-lucide-phone-call',
      hasFeature(FEATURE_FLAGS.JABVOX_DIALER)
        ? [
            routeTab(
              'predictive-dialer',
              t('JABVOX_DIALER.TITLE'),
              'jabvox_dialer_index',
              accountScopedRoute
            ),
          ]
        : [],
      isRouteAllowed
    ),
  ].filter(Boolean);

  return groups;
};

export const isJabvoxNavigationRouteAllowed = (router, shouldShow, to) => {
  const { meta = {} } = router.resolve(to);
  return shouldShow(meta.featureFlag, meta.permissions, meta.installationTypes);
};
