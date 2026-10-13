import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';
import {
  createJabvoxSettingsGroups,
  JABVOX_SETTINGS_CATEGORIES,
} from '../jabvoxSettingsNavigation';

const here = dirname(fileURLToPath(import.meta.url));
const sidebarSource = readFileSync(resolve(here, '../Sidebar.vue'), 'utf8');

describe('Jabvox settings navigation', () => {
  const settingsItems = [
    {
      name: 'Settings Account Settings',
      label: 'General',
      to: { name: 'general' },
    },
    { name: 'Settings Agents', label: 'Agents', to: { name: 'agents' } },
    {
      name: 'Settings Custom Roles',
      label: 'Custom roles',
      to: { name: 'custom_roles_list' },
    },
    { name: 'Settings Inboxes', label: 'Inboxes', to: { name: 'inboxes' } },
    {
      name: 'Settings Jabvox WA Templates',
      label: 'Templates',
      to: { name: 'templates' },
    },
    {
      name: 'Settings Jabvox WA Flows',
      label: 'WhatsApp flows',
      to: { name: 'wa-flows' },
    },
    {
      name: 'Settings Jabvox Bulk WhatsApp',
      label: 'WhatsApp bulk',
      to: { name: 'wa-bulk' },
    },
    {
      name: 'Settings Jabvox WhatsApp Groups',
      label: 'WhatsApp groups',
      to: { name: 'wa-groups' },
    },
    {
      name: 'Settings Jabvox CDR',
      label: 'CDR settings',
      to: { name: 'cdr' },
    },
    {
      name: 'Settings Jabvox Voice Broadcast',
      label: 'Voice broadcast',
      to: { name: 'voice-broadcast' },
    },
    {
      name: 'Settings Jabvox Typifications',
      label: 'Typifications',
      to: { name: 'typifications' },
    },
    { name: 'Settings Jabvox SMS', label: 'SMS', to: { name: 'sms' } },
    { name: 'Settings Jabvox Email', label: 'Email', to: { name: 'email' } },
    { name: 'Settings Jabvox Kanban', label: 'Kanban', to: { name: 'kanban' } },
    {
      name: 'Settings Jabvox Audio Analysis',
      label: 'Audio analysis',
      to: { name: 'audio' },
    },
    {
      name: 'Settings Jabvox Dialer',
      label: 'Dialer',
      to: { name: 'dialer' },
    },
    {
      name: 'Settings Jabvox Management States',
      label: 'Management states',
      to: { name: 'management-states' },
    },
    {
      name: 'Settings Jabvox App States',
      label: 'App states',
      to: { name: 'management-states', query: { tab: 'app' } },
    },
    {
      name: 'Settings Jabvox Campaigns',
      label: 'Campaigns',
      to: { name: 'management-states', query: { tab: 'campaigns' } },
    },
    {
      name: 'Settings Jabvox Forms',
      label: 'Forms',
      to: { name: 'forms' },
    },
    {
      name: 'Settings Jabvox Customization',
      label: 'Customization',
      to: { name: 'customization' },
    },
    {
      name: 'Settings Jabvox Lead Import',
      label: 'Lead import',
      to: { name: 'lead-import' },
    },
    {
      name: 'Settings Jabvox Data Export',
      label: 'Data export',
      to: { name: 'data-export' },
    },
    {
      name: 'Settings Jabvox Products',
      label: 'Products',
      to: { name: 'products' },
    },
    {
      name: 'Settings Jabvox AI Chat',
      label: 'AI chat',
      to: { name: 'ai-chat' },
    },
    {
      name: 'Settings Jabvox Affiliates',
      label: 'Affiliates',
      to: { name: 'affiliates' },
    },
    {
      name: 'Settings Security',
      label: 'Security',
      to: { name: 'security' },
    },
    { name: 'Settings Billing', label: 'Billing', to: { name: 'billing' } },
  ];

  it('groups permitted settings destinations into sidebar categories', () => {
    const groups = createJabvoxSettingsGroups({
      settingsItems,
      categoryLabels: {
        general: 'General',
        team: 'Team',
        conversations: 'Conversations',
        automation: 'Automation',
        calls: 'Calls',
        whatsapp: 'WhatsApp',
        management: 'Management',
        data: 'Data',
        operations: 'Operations',
        affiliates: 'Affiliates',
        security: 'Security',
        billing: 'Billing',
      },
      isRouteAllowed: () => true,
    });

    expect(groups.map(group => group.key)).toEqual([
      'general',
      'team',
      'conversations',
      'calls',
      'whatsapp',
      'management',
      'data',
      'operations',
      'affiliates',
      'security',
      'billing',
    ]);
    expect(
      groups.find(group => group.key === 'team').items.map(item => item.to.name)
    ).toEqual(['agents', 'custom_roles_list']);
    expect(
      groups
        .find(group => group.key === 'management')
        .items.map(item => item.name)
    ).toEqual([
      'Settings Jabvox Typifications',
      'Settings Jabvox Management States',
      'Settings Jabvox App States',
      'Settings Jabvox Campaigns',
      'Settings Jabvox SMS',
      'Settings Jabvox Email',
    ]);
    const destinationsByCategory = Object.fromEntries(
      groups.map(group => [group.key, group.items.map(item => item.to.name)])
    );
    expect(destinationsByCategory).toMatchObject({
      calls: ['cdr', 'voice-broadcast', 'audio', 'dialer'],
      whatsapp: ['templates', 'wa-flows', 'wa-bulk', 'wa-groups'],
      management: [
        'typifications',
        'management-states',
        'management-states',
        'management-states',
        'sms',
        'email',
      ],
      data: ['forms', 'customization', 'lead-import', 'data-export'],
      operations: ['kanban', 'products', 'ai-chat'],
      affiliates: ['affiliates'],
    });
  });

  it('hides destinations denied by route policy and empty categories', () => {
    const groups = createJabvoxSettingsGroups({
      settingsItems,
      categoryLabels: {
        general: 'General',
        team: 'Team',
        conversations: 'Conversations',
        automation: 'Automation',
        calls: 'Calls',
        whatsapp: 'WhatsApp',
        management: 'Management',
        data: 'Data',
        operations: 'Operations',
        affiliates: 'Affiliates',
        security: 'Security',
        billing: 'Billing',
      },
      isRouteAllowed: to => !['agents', 'custom_roles_list'].includes(to.name),
    });

    expect(groups.map(group => group.key)).toEqual([
      'general',
      'conversations',
      'calls',
      'whatsapp',
      'management',
      'data',
      'operations',
      'affiliates',
      'security',
      'billing',
    ]);
    expect(groups.some(group => group.key === 'team')).toBe(false);
  });

  it('assigns every sidebar settings destination to exactly one category', () => {
    const sidebarSettingsNames = [
      ...sidebarSource.matchAll(
        /name: '(Settings [^']+|Conversation Workflow)'/g
      ),
    ]
      .map(([, name]) => name)
      .sort();
    const categorizedSettingsNames = JABVOX_SETTINGS_CATEGORIES.flatMap(
      category => category.itemNames
    ).sort();

    expect(categorizedSettingsNames).toEqual(sidebarSettingsNames);
  });
});
