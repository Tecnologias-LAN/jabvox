export const JABVOX_SETTINGS_CATEGORIES = [
  {
    key: 'general',
    label: 'SIDEBAR.JABVOX_SETTINGS_GENERAL',
    itemNames: [
      'Settings Account Settings',
      'Settings Integrations',
      'Settings Data',
    ],
  },
  {
    key: 'team',
    label: 'SIDEBAR.JABVOX_SETTINGS_TEAM',
    itemNames: [
      'Settings Agents',
      'Settings Teams',
      'Settings Agent Assignment',
      'Settings Custom Roles',
    ],
  },
  {
    key: 'conversations',
    label: 'SIDEBAR.JABVOX_SETTINGS_CONVERSATIONS',
    itemNames: [
      'Settings Inboxes',
      'Settings Labels',
      'Settings Custom Attributes',
      'Settings Macros',
      'Settings Canned Responses',
      'Settings Sla',
      'Conversation Workflow',
    ],
  },
  {
    key: 'automation',
    label: 'SIDEBAR.JABVOX_SETTINGS_AUTOMATION',
    itemNames: [
      'Settings Automation',
      'Settings Jabvox Advanced Automations',
      'Settings Agent Bots',
    ],
  },
  {
    key: 'calls',
    label: 'SIDEBAR.JABVOX_SETTINGS_CALLS',
    itemNames: [
      'Settings Jabvox VoIP',
      'Settings Jabvox CDR',
      'Settings Jabvox Voice Broadcast',
      'Settings Jabvox Audio Analysis',
      'Settings Jabvox Dialer',
    ],
  },
  {
    key: 'whatsapp',
    label: 'SIDEBAR.JABVOX_SETTINGS_WHATSAPP',
    itemNames: [
      'Settings Jabvox WA Templates',
      'Settings Jabvox WA Flows',
      'Settings Jabvox Bulk WhatsApp',
      'Settings Jabvox WhatsApp Groups',
    ],
  },
  {
    key: 'management',
    label: 'SIDEBAR.JABVOX_SETTINGS_MANAGEMENT',
    itemNames: [
      'Settings Jabvox Typifications',
      'Settings Jabvox Management States',
      'Settings Jabvox App States',
      'Settings Jabvox Campaigns',
      'Settings Jabvox SMS',
      'Settings Jabvox Email',
    ],
  },
  {
    key: 'data',
    label: 'SIDEBAR.JABVOX_SETTINGS_DATA',
    itemNames: [
      'Settings Jabvox Forms',
      'Settings Jabvox Customization',
      'Settings Jabvox Lead Import',
      'Settings Jabvox Data Export',
    ],
  },
  {
    key: 'operations',
    label: 'SIDEBAR.JABVOX_SETTINGS_OPERATIONS',
    itemNames: [
      'Settings Jabvox Kanban',
      'Settings Jabvox Products',
      'Settings Jabvox AI Chat',
    ],
  },
  {
    key: 'affiliates',
    label: 'SIDEBAR.JABVOX_SETTINGS_AFFILIATES',
    itemNames: ['Settings Jabvox Affiliates'],
  },
  {
    key: 'security',
    label: 'SIDEBAR.JABVOX_SETTINGS_SECURITY',
    itemNames: [
      'Settings Audit Logs',
      'Settings Security',
      'Settings Jabvox Field Security',
      'Settings Jabvox IP Whitelist',
    ],
  },
  {
    key: 'billing',
    label: 'SIDEBAR.JABVOX_SETTINGS_BILLING',
    itemNames: [
      'Settings Billing',
      'Settings Jabvox Saldo',
      'Settings Jabvox AI Budget',
    ],
  },
];

export const getJabvoxSettingsCategoryLabels = t => ({
  general: t('SIDEBAR.JABVOX_SETTINGS_GENERAL'),
  team: t('SIDEBAR.JABVOX_SETTINGS_TEAM'),
  conversations: t('SIDEBAR.JABVOX_SETTINGS_CONVERSATIONS'),
  automation: t('SIDEBAR.JABVOX_SETTINGS_AUTOMATION'),
  calls: t('SIDEBAR.JABVOX_SETTINGS_CALLS'),
  whatsapp: t('SIDEBAR.JABVOX_SETTINGS_WHATSAPP'),
  management: t('SIDEBAR.JABVOX_SETTINGS_MANAGEMENT'),
  data: t('SIDEBAR.JABVOX_SETTINGS_DATA'),
  operations: t('SIDEBAR.JABVOX_SETTINGS_OPERATIONS'),
  affiliates: t('SIDEBAR.JABVOX_SETTINGS_AFFILIATES'),
  security: t('SIDEBAR.JABVOX_SETTINGS_SECURITY'),
  billing: t('SIDEBAR.JABVOX_SETTINGS_BILLING'),
});

export const createJabvoxSettingsGroups = ({
  settingsItems,
  categoryLabels,
  isRouteAllowed,
}) =>
  JABVOX_SETTINGS_CATEGORIES.map(category => ({
    ...category,
    label: categoryLabels[category.key],
    items: category.itemNames
      .map(name => settingsItems.find(item => item.name === name))
      .filter(item => item?.to && isRouteAllowed(item.to)),
  })).filter(category => category.items.length > 0);
