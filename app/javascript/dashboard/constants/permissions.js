// Jabvox per-module permissions, grouped for display. Each key must match
// CustomRole::JABVOX_PERMISSIONS (backend) and have an i18n label under
// CUSTOM_ROLE.PERMISSIONS.<KEY uppercased>. Groups render as sections in the
// create/edit-role form.
export const JABVOX_PERMISSION_GROUPS = [
  {
    module: 'leads',
    permissions: [
      'jabvox_leads_view_all',
      'jabvox_leads_assign',
      'jabvox_leads_edit',
      'jabvox_leads_delete',
    ],
  },
  {
    module: 'kanban',
    permissions: ['jabvox_kanban_view_all', 'jabvox_kanban_manage'],
  },
  {
    module: 'tasks',
    permissions: ['jabvox_tasks_view_all', 'jabvox_tasks_manage'],
  },
  {
    module: 'cdr',
    permissions: ['jabvox_cdr_view_reports', 'jabvox_cdr_manage'],
  },
  {
    module: 'audio',
    permissions: [
      'jabvox_audio_access',
      'jabvox_audio_view_reports',
      'jabvox_audio_manage',
    ],
  },
  {
    module: 'ai_chat',
    permissions: ['jabvox_ai_chat_use', 'jabvox_ai_chat_manage'],
  },
  {
    module: 'whatsapp_templates',
    permissions: ['jabvox_whatsapp_templates_manage'],
  },
  {
    module: 'analytics',
    permissions: ['jabvox_analytics_access', 'jabvox_analytics_manage'],
  },
  {
    module: 'lead_import',
    permissions: ['jabvox_lead_import_manage'],
  },
  {
    module: 'data_export',
    permissions: ['jabvox_data_export_manage'],
  },
  {
    module: 'bulk_whatsapp',
    permissions: ['jabvox_bulk_whatsapp_send'],
  },
  {
    module: 'whatsapp_groups',
    permissions: ['jabvox_whatsapp_groups_manage'],
  },
  {
    module: 'custom_data',
    permissions: ['jabvox_custom_data_manage'],
  },
  {
    module: 'dialer',
    permissions: ['jabvox_dialer_use', 'jabvox_dialer_manage'],
  },
  {
    module: 'click_to_call',
    permissions: ['jabvox_click_to_call_use'],
  },
  {
    module: 'internal_chat',
    permissions: ['jabvox_internal_chat_use'],
  },
  {
    module: 'calendar',
    permissions: ['jabvox_calendar_manage'],
  },
  {
    module: 'forms',
    permissions: ['jabvox_forms_manage'],
  },
  {
    module: 'sms',
    permissions: ['jabvox_sms_view', 'jabvox_sms_manage'],
  },
  {
    module: 'email',
    permissions: ['jabvox_email_manage'],
  },
  {
    module: 'saldo',
    permissions: ['jabvox_saldo_manage'],
  },
  {
    module: 'voip',
    permissions: ['jabvox_voip_manage'],
  },
  {
    module: 'integrations',
    permissions: ['jabvox_integration_manage'],
  },
  {
    module: 'ip_whitelist',
    permissions: ['jabvox_ip_whitelist_manage'],
  },
  {
    module: 'products',
    permissions: ['jabvox_products_manage', 'jabvox_orders_manage'],
  },
  {
    module: 'typifications',
    permissions: ['jabvox_typifications_manage'],
  },
  {
    module: 'management_states',
    permissions: ['jabvox_management_states_manage'],
  },
  {
    module: 'field_visibilities',
    permissions: ['jabvox_field_visibilities_manage'],
  },
  {
    module: 'sales_reports',
    permissions: ['jabvox_sales_reports_manage'],
  },
  {
    module: 'campaigns',
    permissions: ['jabvox_campaigns_manage'],
  },
  {
    module: 'affiliates',
    permissions: ['jabvox_affiliates_manage'],
  },
  {
    module: 'app_states',
    permissions: ['jabvox_app_states_manage'],
  },
  {
    module: 'reports',
    permissions: ['jabvox_reports_view'],
  },
];

export const JABVOX_CUSTOM_ROLE_PERMISSIONS = JABVOX_PERMISSION_GROUPS.flatMap(
  group => group.permissions
);

export const AVAILABLE_CUSTOM_ROLE_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
  'contact_manage',
  'report_manage',
  'knowledge_base_manage',
  ...JABVOX_CUSTOM_ROLE_PERMISSIONS,
];

export const ROLES = ['agent', 'administrator'];

export const CONVERSATION_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

export const MANAGE_ALL_CONVERSATION_PERMISSIONS = 'conversation_manage';

export const CONVERSATION_UNASSIGNED_PERMISSIONS =
  'conversation_unassigned_manage';

export const CONVERSATION_PARTICIPATING_PERMISSIONS =
  'conversation_participating_manage';

export const CONTACT_PERMISSIONS = 'contact_manage';

export const REPORTS_PERMISSIONS = 'report_manage';

export const PORTAL_PERMISSIONS = 'knowledge_base_manage';

export const ASSIGNEE_TYPE_TAB_PERMISSIONS = {
  me: {
    count: 'mineCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  unassigned: {
    count: 'unAssignedCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_UNASSIGNED_PERMISSIONS,
    ],
  },
  all: {
    count: 'allCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_PARTICIPATING_PERMISSIONS,
    ],
  },
};
