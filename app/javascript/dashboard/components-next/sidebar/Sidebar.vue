<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useJabvoxPermissions } from 'dashboard/composables/useJabvoxPermissions';
import { useWindowSize, useEventListener } from '@vueuse/core';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { aiBudgetAPI } from 'dashboard/api/jabvox/aiBudget';

import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import SidebarChangelogCard from './SidebarChangelogCard.vue';
import SidebarChangelogButton from './SidebarChangelogButton.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import SidebarNotificationBell from './SidebarNotificationBell.vue';
import SidebarQuickPreferences from './SidebarQuickPreferences.vue';
import {
  createJabvoxModuleNavigation,
  isJabvoxNavigationRouteAllowed,
} from './jabvoxModuleNavigation';
import {
  createJabvoxSettingsGroups,
  getJabvoxSettingsCategoryLabels,
} from './jabvoxSettingsNavigation';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'closeKeyShortcutModal',
  'openKeyShortcutModal',
  'showCreateAccountModal',
  'closeMobileSidebar',
  'settingsNavigation',
]);

const JABVOX_LOGO_URL = '/jabvox/public/logo.png';

const { accountScopedRoute, isOnJabvoxCloud } = useAccount();
const { isEnterprise } = useConfig();
const { shouldShow } = usePolicy();
const { jabvoxCan } = useJabvoxPermissions();
const store = useStore();
const route = useRoute();
const router = useRouter();

// Calls run on the enterprise-only API (cloud runs enterprise); hide the entry
// on community so it doesn't lead to a dashboard/CTA the backend can't serve.
const isCallsAvailable = computed(() => isOnJabvoxCloud.value || isEnterprise);
const { t } = useI18n();

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);
const isRTL = useMapGetter('accounts/isRTL');

const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const saldoStatus = useMapGetter('jabvoxSaldo/getStatus');
const aiBudgetBalance = ref(null);
const isAiBalanceLoading = ref(false);
let aiBalanceRequestId = 0;

const isSaldoEnabled = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.JABVOX_SALDO)
);
const canViewAiBalance = computed(
  () =>
    shouldShow('', ['administrator']) &&
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.JABVOX_AI_CHAT
    )
);

const appStatesForPresence = useMapGetter('jabvoxAppStates/getActiveStates');
const currentAppState = useMapGetter('jabvoxAppStates/getCurrentUserAppState');
const presenceDropdownOpen = ref(false);
const presenceColor = computed(() => currentAppState.value?.color || '#22c55e');
const presenceName = computed(
  () =>
    currentAppState.value?.name ||
    t('JABVOX_MANAGEMENT_STATES.APP_STATES.ACTIVE_DEFAULT')
);
const setPresence = async stateId => {
  await store.dispatch('jabvoxAppStates/setPresence', stateId);
  presenceDropdownOpen.value = false;
};

const hasAdvancedAssignment = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.ADVANCED_ASSIGNMENT
  );
});

const hasConversationUnreadCounts = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
  );
});

const hasDataImport = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.DATA_IMPORT
  );
});

const fetchConversationUnreadCounts = ([currentAccountId, isEnabled]) => {
  if (!currentAccountId) return;

  if (!isEnabled) {
    store.dispatch('conversationUnreadCounts/clear');
    return;
  }

  store.dispatch('conversationUnreadCounts/get');
};

const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};

const {
  sidebarWidth,
  isCollapsed,
  setSidebarWidth,
  saveWidth,
  snapToCollapsed,
  snapToExpanded,
  COLLAPSED_THRESHOLD,
} = useSidebarResize();

const sidebarToggleLabel = computed(() =>
  isCollapsed.value ? t('SIDEBAR.EXPAND_MENU') : t('SIDEBAR.COLLAPSE_MENU')
);

// On mobile, sidebar is always expanded (flyout mode)
const isEffectivelyCollapsed = computed(
  () => !isMobile.value && isCollapsed.value
);

// Resize handle logic
const isResizing = ref(false);
const startX = ref(0);
const startWidth = ref(0);

provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: isEffectivelyCollapsed,
  sidebarWidth,
  isResizing,
});

// Get clientX from mouse or touch event
const getClientX = event =>
  event.touches ? event.touches[0].clientX : event.clientX;

const onResizeStart = event => {
  isResizing.value = true;
  startX.value = getClientX(event);
  startWidth.value = sidebarWidth.value;
  Object.assign(document.body.style, {
    cursor: 'col-resize',
    userSelect: 'none',
  });
  // Prevent default to avoid scrolling on touch
  event.preventDefault();
};

const onResizeMove = event => {
  if (!isResizing.value) return;

  const delta = isRTL.value
    ? startX.value - getClientX(event)
    : getClientX(event) - startX.value;
  setSidebarWidth(startWidth.value + delta);
};

const onResizeEnd = () => {
  if (!isResizing.value) return;

  isResizing.value = false;
  Object.assign(document.body.style, { cursor: '', userSelect: '' });

  // Snap to collapsed state if below threshold
  if (sidebarWidth.value < COLLAPSED_THRESHOLD) {
    snapToCollapsed();
  } else {
    saveWidth();
  }
};

const onResizeHandleDoubleClick = () => {
  if (isCollapsed.value) snapToExpanded();
  else snapToCollapsed();
};

const toggleSidebarWidth = () => {
  if (isCollapsed.value) snapToExpanded();
  else snapToCollapsed();
};

// Support both mouse and touch events
useEventListener(document, 'mousemove', onResizeMove);
useEventListener(document, 'mouseup', onResizeEnd);
useEventListener(document, 'touchmove', onResizeMove, { passive: false });
useEventListener(document, 'touchend', onResizeEnd);

onMounted(() => {
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  store.dispatch('customViews/get', 'conversation');
  // Las vistas de contacto ya no se pintan en el menú, pero la lista de contactos y el
  // diálogo de exportación las leen del store sin cargarlas ellos mismos: si se quita este
  // dispatch, sus selectores de segmento se quedan vacíos.
  store.dispatch('customViews/get', 'contact');
  if (isSaldoEnabled.value) {
    store.dispatch('jabvoxSaldo/fetchStatus');
  }
  // Load the internal-chat unread total so the sidebar badge shows without opening the chat.
  if (
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.JABVOX_INTERNAL_CHAT
    )
  ) {
    store.dispatch('jabvoxInternalChat/fetchUnreadCount');
  }
  store.dispatch('jabvoxFieldVisibilities/fetchMyVisibilities');
  store.dispatch('jabvoxAppStates/fetchStates');
});

watch(
  accountId,
  currentAccountId => {
    if (!currentAccountId) return;

    store.commit('labels/SET_LABELS', []);
    store.commit('inboxes/SET_INBOXES', []);
    store.dispatch('labels/get');
    store.dispatch('inboxes/get');
  },
  { immediate: true }
);

watch([accountId, hasConversationUnreadCounts], fetchConversationUnreadCounts, {
  immediate: true,
});

const closeMobileSidebar = () => {
  if (!props.isMobileSidebarOpen) return;
  emit('closeMobileSidebar');
};

const saldoLabel = computed(() => {
  if (!saldoStatus.value) {
    return '...';
  }

  const balance = Number(saldoStatus.value.balance || 0);
  const formatted = balance.toLocaleString('es-CO', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });
  return `$${formatted} COP`;
});

const aiBalanceLabel = computed(() => {
  if (isAiBalanceLoading.value) return '...';
  if (!aiBudgetBalance.value?.connected) return '—';
  if (aiBudgetBalance.value.unlimited) {
    return t('JABVOX_AI_BUDGET.UNLIMITED');
  }
  return `$${Number(aiBudgetBalance.value.remaining_usd || 0).toFixed(2)} USD`;
});

const aiBalanceColor = computed(() => {
  if (isAiBalanceLoading.value || !aiBudgetBalance.value?.connected) {
    return 'text-n-slate-11';
  }
  if (
    aiBudgetBalance.value.unlimited ||
    Number(aiBudgetBalance.value.remaining_usd || 0) > 0
  ) {
    return 'text-n-teal-11';
  }
  return 'text-red-500';
});

const fetchAiBalance = async ([currentAccountId, enabled]) => {
  aiBalanceRequestId += 1;
  const requestId = aiBalanceRequestId;
  aiBudgetBalance.value = null;
  isAiBalanceLoading.value = Boolean(currentAccountId && enabled);
  if (!currentAccountId || !enabled) return;

  try {
    const { data } = await aiBudgetAPI.get();
    if (requestId === aiBalanceRequestId) aiBudgetBalance.value = data || null;
  } catch {
    if (requestId === aiBalanceRequestId) {
      useAlert(t('JABVOX_AI_BUDGET.LOAD_ERROR'));
    }
  } finally {
    if (requestId === aiBalanceRequestId) isAiBalanceLoading.value = false;
  }
};

watch([accountId, canViewAiBalance], fetchAiBalance, { immediate: true });

const saldoBalanceColor = computed(() => {
  if (!saldoStatus.value) return 'text-n-slate-11';
  const balance = Number(saldoStatus.value.balance || 0);
  if (balance > 0) return 'text-green-500';
  if (balance < 0) return 'text-red-500';
  return 'text-amber-500';
});

const rawMenuItems = computed(() => {
  const moduleNavigation = createJabvoxModuleNavigation({
    t,
    accountScopedRoute,
    hasFeature: flag => isFeatureEnabledonAccount.value(accountId.value, flag),
    isRouteAllowed: to =>
      isJabvoxNavigationRouteAllowed(router, shouldShow, to),
    isCallsAvailable: isCallsAvailable.value,
    canViewJabvoxReports: jabvoxCan('jabvox_reports_view'),
  });

  return [
    {
      name: 'Dashboard',
      label: t('SIDEBAR.HOME'),
      icon: 'i-lucide-layout-dashboard',
      to: accountScopedRoute('account_dashboard'),
      activeOn: ['account_dashboard'],
    },
    ...moduleNavigation.map(
      ({ name, label, icon, to, activeOn, getterKeys }) => ({
        name,
        label,
        icon,
        to,
        activeOn,
        getterKeys,
      })
    ),
    {
      name: 'Settings',
      label: t('SIDEBAR.SETTINGS'),
      icon: 'i-lucide-bolt',
      children: [
        {
          name: 'Settings Account Settings',
          label: t('SIDEBAR.ACCOUNT_SETTINGS'),
          icon: 'i-lucide-briefcase',
          to: accountScopedRoute('general_settings_index'),
        },
        {
          name: 'Settings Agents',
          label: t('SIDEBAR.AGENTS'),
          icon: 'i-lucide-square-user',
          to: accountScopedRoute('agent_list'),
        },
        {
          name: 'Settings Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: [
            'settings_teams_list',
            'settings_teams_new',
            'settings_teams_finish',
            'settings_teams_add_agents',
            'settings_teams_show',
            'settings_teams_edit',
            'settings_teams_edit_members',
            'settings_teams_edit_finish',
          ],
          to: accountScopedRoute('settings_teams_list'),
        },
        ...(hasAdvancedAssignment.value
          ? [
              {
                name: 'Settings Agent Assignment',
                label: t('SIDEBAR.AGENT_ASSIGNMENT'),
                icon: 'i-lucide-user-cog',
                activeOn: [
                  'assignment_policy_index',
                  'agent_assignment_policy_index',
                  'agent_assignment_policy_create',
                  'agent_assignment_policy_edit',
                  'agent_capacity_policy_index',
                  'agent_capacity_policy_create',
                  'agent_capacity_policy_edit',
                ],
                to: accountScopedRoute('assignment_policy_index'),
              },
            ]
          : []),
        {
          name: 'Settings Inboxes',
          label: t('SIDEBAR.INBOXES'),
          icon: 'i-lucide-inbox',
          activeOn: [
            'settings_inbox_list',
            'settings_inbox_show',
            'settings_inbox_new',
            'settings_inbox_finish',
            'settings_inboxes_page_channel',
            'settings_inboxes_add_agents',
          ],
          to: accountScopedRoute('settings_inbox_list'),
        },
        {
          name: 'Settings Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tags',
          to: accountScopedRoute('labels_list'),
        },
        {
          name: 'Settings Custom Attributes',
          label: t('SIDEBAR.CUSTOM_ATTRIBUTES'),
          icon: 'i-lucide-code',
          to: accountScopedRoute('attributes_list'),
        },
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.AUTOMATION'),
          icon: 'i-lucide-repeat',
          to: accountScopedRoute('automation_list'),
        },
        ...(isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_ADVANCED_AUTOMATIONS
        )
          ? [
              {
                name: 'Settings Jabvox Advanced Automations',
                label: t('SIDEBAR.ADVANCED_AUTOMATION'),
                icon: 'i-lucide-workflow',
                to: accountScopedRoute('jabvox_advanced_automations_settings'),
                activeOn: ['jabvox_advanced_automations_settings'],
              },
            ]
          : []),
        {
          name: 'Settings Agent Bots',
          label: t('SIDEBAR.AGENT_BOTS'),
          icon: 'i-lucide-bot',
          to: accountScopedRoute('agent_bots'),
        },
        {
          name: 'Settings Macros',
          label: t('SIDEBAR.MACROS'),
          icon: 'i-lucide-toy-brick',
          to: accountScopedRoute('macros_wrapper'),
        },
        ...(isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.CANNED_RESPONSES
        )
          ? [
              {
                name: 'Settings Canned Responses',
                label: t('SIDEBAR.CANNED_RESPONSES'),
                icon: 'i-lucide-message-square-quote',
                to: accountScopedRoute('canned_list'),
              },
            ]
          : []),
        {
          name: 'Settings Integrations',
          label: t('SIDEBAR.INTEGRATIONS'),
          icon: 'i-lucide-blocks',
          to: accountScopedRoute('settings_applications'),
        },
        ...(hasDataImport.value
          ? [
              {
                name: 'Settings Data',
                label: t('SIDEBAR.DATA'),
                icon: 'i-lucide-database',
                to: accountScopedRoute('settings_data_imports'),
              },
            ]
          : []),
        ...(isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.AUDIT_LOGS
        )
          ? [
              {
                name: 'Settings Audit Logs',
                label: t('SIDEBAR.AUDIT_LOGS'),
                icon: 'i-lucide-briefcase',
                to: accountScopedRoute('auditlogs_list'),
              },
            ]
          : []),
        // Only when the account has the custom-roles module enabled (the route
        // guard also blocks direct-URL access when it's off).
        ...(isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.CUSTOM_ROLES
        )
          ? [
              {
                name: 'Settings Custom Roles',
                label: t('SIDEBAR.CUSTOM_ROLES'),
                icon: 'i-lucide-shield-plus',
                to: accountScopedRoute('custom_roles_list'),
              },
            ]
          : []),
        ...(isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.SLA)
          ? [
              {
                name: 'Settings Sla',
                label: t('SIDEBAR.SLA'),
                icon: 'i-lucide-clock-alert',
                to: accountScopedRoute('sla_list'),
              },
            ]
          : []),
        ...(isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_CONVERSATION_WORKFLOW
        )
          ? [
              {
                name: 'Conversation Workflow',
                label: t('SIDEBAR.CONVERSATION_WORKFLOW'),
                icon: 'i-lucide-workflow',
                to: accountScopedRoute('conversation_workflow_index'),
              },
            ]
          : []),
        ...(isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.SAML)
          ? [
              {
                name: 'Settings Security',
                label: t('SIDEBAR.SECURITY'),
                icon: 'i-lucide-shield',
                to: accountScopedRoute('security_settings_index'),
              },
            ]
          : []),
        {
          name: 'Settings Billing',
          label: t('SIDEBAR.BILLING'),
          icon: 'i-lucide-credit-card',
          to: accountScopedRoute('billing_settings_index'),
        },
        ...(jabvoxCan('jabvox_field_visibilities_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_FIELD_SECURITY
        )
          ? [
              {
                name: 'Settings Jabvox Field Security',
                label: t('JABVOX_FIELD_SECURITY.SIDEBAR_LABEL'),
                icon: 'i-lucide-shield-check',
                to: accountScopedRoute('jabvox_field_security_index'),
                activeOn: ['jabvox_field_security_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_kanban_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_KANBAN
        )
          ? [
              {
                name: 'Settings Jabvox Kanban',
                label: t('SIDEBAR.JABVOX_KANBAN'),
                icon: 'i-lucide-kanban',
                activeOn: [
                  'jabvox_kanban_funnels_index',
                  'jabvox_kanban_funnels_new',
                  'jabvox_kanban_funnels_edit',
                  'jabvox_kanban_stages',
                ],
                to: accountScopedRoute('jabvox_kanban_funnels_index'),
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_products_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_PRODUCTS
        )
          ? [
              {
                name: 'Settings Jabvox Products',
                label: t('SIDEBAR.JABVOX_PRODUCTS'),
                icon: 'i-lucide-shopping-cart',
                to: accountScopedRoute('jabvox_products_index'),
                activeOn: ['jabvox_products_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_voip_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_VOIP
        )
          ? [
              {
                name: 'Settings Jabvox VoIP',
                label: t('SIDEBAR.JABVOX_VOIP'),
                icon: 'i-lucide-phone',
                to: accountScopedRoute('jabvox_voip_index'),
                activeOn: ['jabvox_voip_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_cdr_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_CDR
        )
          ? [
              {
                name: 'Settings Jabvox CDR',
                label: t('SIDEBAR.JABVOX_CDR'),
                icon: 'i-lucide-phone-call',
                to: accountScopedRoute('jabvox_cdr_settings_index'),
                activeOn: ['jabvox_cdr_settings_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_whatsapp_templates_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_WHATSAPP_TEMPLATES
        )
          ? [
              {
                name: 'Settings Jabvox WA Templates',
                label: t('SIDEBAR.JABVOX_WHATSAPP_TEMPLATES'),
                icon: 'i-lucide-message-square-text',
                to: accountScopedRoute(
                  'jabvox_whatsapp_templates_settings_index'
                ),
                activeOn: ['jabvox_whatsapp_templates_settings_index'],
              },
            ]
          : []),
        // WhatsApp Flows (formularios interactivos) es un módulo distinto de
        // "Plantillas WA". A diferencia de templates, el backend exige
        // jabvox_whatsapp_flows_manage en TODAS las acciones del controller,
        // incluido el listado (BaseController#ensure_can_manage no distingue
        // lectura de escritura) — así que se gatea igual aquí, o un agente
        // sin el permiso vería la entrada y un 403 al abrirla.
        ...(jabvoxCan('jabvox_whatsapp_flows_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_WHATSAPP_FLOWS
        )
          ? [
              {
                name: 'Settings Jabvox WA Flows',
                label: t('SIDEBAR.JABVOX_WHATSAPP_FLOWS'),
                icon: 'i-lucide-list-tree',
                to: accountScopedRoute('jabvox_whatsapp_flows_settings_index'),
                activeOn: [
                  'jabvox_whatsapp_flows_settings_index',
                  'jabvox_whatsapp_flows_builder',
                ],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_bulk_whatsapp_send') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_BULK_WHATSAPP
        )
          ? [
              {
                name: 'Settings Jabvox Bulk WhatsApp',
                label: t('SIDEBAR.JABVOX_BULK_WHATSAPP'),
                icon: 'i-lucide-send-horizontal',
                to: accountScopedRoute('jabvox_bulk_whatsapp_settings_index'),
                activeOn: ['jabvox_bulk_whatsapp_settings_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_whatsapp_groups_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_WHATSAPP_GROUPS
        )
          ? [
              {
                name: 'Settings Jabvox WhatsApp Groups',
                label: t('SIDEBAR.JABVOX_WHATSAPP_GROUPS'),
                icon: 'i-lucide-users-round',
                to: accountScopedRoute('jabvox_whatsapp_groups_settings_index'),
                activeOn: ['jabvox_whatsapp_groups_settings_index'],
              },
            ]
          : []),
        ...((jabvoxCan('jabvox_voice_broadcast_manage') ||
          jabvoxCan('jabvox_dialer_manage')) &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_VOICE_BROADCAST
        )
          ? [
              {
                name: 'Settings Jabvox Voice Broadcast',
                label: t('SIDEBAR.JABVOX_VOICE_BROADCAST'),
                icon: 'i-lucide-megaphone',
                to: accountScopedRoute('jabvox_voice_broadcast_settings_index'),
                activeOn: ['jabvox_voice_broadcast_settings_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_audio_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_AUDIO_ANALYSIS
        )
          ? [
              {
                name: 'Settings Jabvox Audio Analysis',
                label: t('SIDEBAR.JABVOX_AUDIO_ANALYSIS'),
                icon: 'i-lucide-audio-lines',
                to: accountScopedRoute('jabvox_audio_analysis_settings_index'),
                activeOn: ['jabvox_audio_analysis_settings_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_lead_import_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_LEAD_IMPORT
        )
          ? [
              {
                name: 'Settings Jabvox Lead Import',
                label: t('SIDEBAR.JABVOX_LEAD_IMPORT'),
                icon: 'i-lucide-database',
                to: accountScopedRoute('jabvox_lead_import_settings_index'),
                activeOn: ['jabvox_lead_import_settings_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_data_export_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_DATA_EXPORT
        )
          ? [
              {
                name: 'Settings Jabvox Data Export',
                label: t('SIDEBAR.JABVOX_DATA_EXPORT'),
                icon: 'i-lucide-database-zap',
                to: accountScopedRoute('jabvox_data_export_settings_index'),
                activeOn: ['jabvox_data_export_settings_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_typifications_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_CLICK_TO_CALL
        )
          ? [
              {
                name: 'Settings Jabvox Typifications',
                label: t('SIDEBAR.JABVOX_TYPIFICATIONS'),
                icon: 'i-lucide-tags',
                to: accountScopedRoute('jabvox_typifications_index'),
                activeOn: ['jabvox_typifications_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_saldo_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_SALDO
        )
          ? [
              {
                name: 'Settings Jabvox Saldo',
                label: t('SIDEBAR.JABVOX_SALDO'),
                icon: 'i-lucide-wallet',
                to: accountScopedRoute('jabvox_saldo_index'),
                activeOn: ['jabvox_saldo_index'],
              },
            ]
          : []),
        ...(isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_AI_CHAT
        )
          ? [
              {
                name: 'Settings Jabvox AI Budget',
                label: t('SIDEBAR.JABVOX_AI_BUDGET'),
                icon: 'i-lucide-coins',
                to: accountScopedRoute('jabvox_ai_budget_index'),
                activeOn: ['jabvox_ai_budget_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_sms_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_SMS
        )
          ? [
              {
                name: 'Settings Jabvox SMS',
                label: t('SIDEBAR.JABVOX_SMS'),
                icon: 'i-lucide-message-square',
                to: accountScopedRoute('jabvox_sms_index'),
                activeOn: ['jabvox_sms_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_ip_whitelist_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_IP_WHITELIST
        )
          ? [
              {
                name: 'Settings Jabvox IP Whitelist',
                label: t('SIDEBAR.JABVOX_IP_WHITELIST'),
                icon: 'i-lucide-shield',
                to: accountScopedRoute('jabvox_ip_whitelist_index'),
                activeOn: ['jabvox_ip_whitelist_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_ai_chat_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_AI_CHAT
        )
          ? [
              {
                name: 'Settings Jabvox AI Chat',
                label: t('JABVOX_AI_CHAT.CONFIG_SIDEBAR_LABEL'),
                icon: 'i-ri-robot-2-line',
                to: accountScopedRoute('jabvox_ai_chat_settings_index'),
                activeOn: ['jabvox_ai_chat_settings_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_management_states_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_MANAGEMENT_STATES
        )
          ? [
              {
                name: 'Settings Jabvox Management States',
                label: t('JABVOX_MANAGEMENT_STATES.SIDEBAR_LABEL'),
                icon: 'i-lucide-tag',
                to: accountScopedRoute(
                  'jabvox_management_states_index',
                  {},
                  { tab: 'management' }
                ),
                activeOn: ['jabvox_management_states_index'],
              },
              {
                name: 'Settings Jabvox App States',
                label: t('JABVOX_MANAGEMENT_STATES.TABS.APP'),
                icon: 'i-lucide-smartphone',
                to: accountScopedRoute(
                  'jabvox_management_states_index',
                  {},
                  { tab: 'app' }
                ),
                activeOn: ['jabvox_management_states_index'],
              },
              {
                name: 'Settings Jabvox Campaigns',
                label: t('JABVOX_MANAGEMENT_STATES.TABS.CAMPAIGNS'),
                icon: 'i-lucide-megaphone',
                to: accountScopedRoute(
                  'jabvox_management_states_index',
                  {},
                  { tab: 'campaigns' }
                ),
                activeOn: ['jabvox_management_states_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_dialer_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_DIALER
        )
          ? [
              {
                name: 'Settings Jabvox Dialer',
                label: t('JABVOX_DIALER.SETTINGS.TITLE'),
                icon: 'i-lucide-phone-call',
                to: accountScopedRoute('jabvox_dialer_settings'),
                activeOn: ['jabvox_dialer_settings'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_affiliates_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_AFFILIATES
        )
          ? [
              {
                name: 'Settings Jabvox Affiliates',
                label: t('JABVOX_AFFILIATES.TITLE'),
                icon: 'i-lucide-users-round',
                to: accountScopedRoute('jabvox_affiliates_index'),
                activeOn: ['jabvox_affiliates_index'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_email_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_EMAIL
        )
          ? [
              {
                name: 'Settings Jabvox Email',
                label: t('JABVOX_EMAIL.SIDEBAR_LABEL'),
                icon: 'i-lucide-mail',
                to: accountScopedRoute('jabvox_email_settings'),
                activeOn: ['jabvox_email_settings'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_forms_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_FORMS
        )
          ? [
              {
                name: 'Settings Jabvox Forms',
                label: t('JABVOX_FORMS.SIDEBAR_LABEL'),
                icon: 'i-lucide-file-text',
                to: accountScopedRoute('jabvox_forms_settings'),
                activeOn: ['jabvox_forms_settings'],
              },
            ]
          : []),
        ...(jabvoxCan('jabvox_custom_data_manage') &&
        isFeatureEnabledonAccount.value(
          accountId.value,
          FEATURE_FLAGS.JABVOX_CUSTOMIZATION
        )
          ? [
              {
                name: 'Settings Jabvox Customization',
                label: t('JABVOX_CUSTOMIZATION.SIDEBAR_LABEL'),
                icon: 'i-lucide-sliders-horizontal',
                to: accountScopedRoute('jabvox_customization_settings'),
                activeOn: ['jabvox_customization_settings'],
              },
            ]
          : []),
      ],
    },
  ];
});

const settingsNavigationItems = computed(
  () =>
    rawMenuItems.value.find(item => item.name === 'Settings')?.children || []
);

const settingsSidebarGroups = computed(() =>
  createJabvoxSettingsGroups({
    settingsItems: settingsNavigationItems.value,
    categoryLabels: getJabvoxSettingsCategoryLabels(t),
    isRouteAllowed: to =>
      isJabvoxNavigationRouteAllowed(router, shouldShow, to),
  }).map(category => {
    const activeSettingPath = category.items.some(setting => {
      const settingPath = router.resolve(setting.to).path;
      return (
        route.path === settingPath || route.path.startsWith(`${settingPath}/`)
      );
    });
    const activeOn = category.items.flatMap(setting => [
      setting.to?.name,
      ...(setting.activeOn || []),
    ]);

    return {
      name: `Settings ${category.key}`,
      label: category.label,
      icon: category.items[0]?.icon || 'i-lucide-settings-2',
      to: category.items[0].to,
      activeOn: [
        ...new Set(activeOn.concat(activeSettingPath ? [route.name] : [])),
      ],
    };
  })
);

const menuItems = computed(() =>
  rawMenuItems.value.map(item => {
    if (item.name !== 'Settings') return item;

    const firstAllowedItem = settingsSidebarGroups.value[0];

    return {
      ...item,
      to: firstAllowedItem?.to || accountScopedRoute('general_settings_index'),
      activeOn: settingsSidebarGroups.value.flatMap(group => group.activeOn),
      children: settingsSidebarGroups.value,
    };
  })
);

watch(settingsNavigationItems, items => emit('settingsNavigation', items), {
  immediate: true,
});
</script>

<template>
  <header
    v-if="!isMobile"
    class="absolute inset-x-0 top-0 z-[60] flex h-16 border-b border-[#8FC4C2] bg-white/95 shadow-sm backdrop-blur"
  >
    <div
      class="flex h-full flex-shrink-0 items-center gap-2 overflow-hidden bg-gradient-to-r from-[#DAEBDB] to-[#A8D5D3] px-2"
      :style="{ width: `${sidebarWidth}px` }"
    >
      <SidebarAccountSwitcher
        v-if="isEffectivelyCollapsed"
        is-collapsed
        @show-create-account-modal="emit('showCreateAccountModal')"
      />
      <template v-else>
        <img
          :src="JABVOX_LOGO_URL"
          alt="Jabvox"
          class="h-10 w-auto max-w-[112px] flex-shrink-0 object-contain"
        />
        <div class="h-6 w-px flex-shrink-0 bg-[#5B9690]/50" />
        <SidebarAccountSwitcher
          class="min-w-0 flex-1"
          @show-create-account-modal="emit('showCreateAccountModal')"
        />
      </template>
    </div>
    <div class="flex min-w-0 flex-1 items-center justify-between gap-3 px-4">
      <button
        type="button"
        class="grid size-9 flex-shrink-0 place-items-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-label="sidebarToggleLabel"
        :title="sidebarToggleLabel"
        @click="toggleSidebarWidth"
      >
        <span class="i-lucide-menu size-5" aria-hidden="true" />
      </button>
      <div class="flex min-w-0 items-center gap-3">
        <div
          v-if="isSaldoEnabled"
          class="hidden items-center gap-2 rounded-xl border border-n-weak bg-n-background px-3 py-2 lg:flex"
        >
          <span
            class="i-lucide-wallet size-4 flex-shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('JABVOX_SALDO.HEADER.LABEL') }}
          </span>
          <span class="text-sm font-semibold" :class="saldoBalanceColor">
            {{ saldoLabel }}
          </span>
        </div>
        <div
          v-if="canViewAiBalance"
          class="hidden items-center gap-2 rounded-xl border border-n-weak bg-n-background px-3 py-2 xl:flex"
        >
          <span
            class="i-lucide-sparkles size-4 flex-shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('SIDEBAR.JABVOX_AI_BUDGET') }}
          </span>
          <span class="text-sm font-semibold" :class="aiBalanceColor">
            {{ aiBalanceLabel }}
          </span>
        </div>
        <div
          v-on-click-outside="() => (presenceDropdownOpen = false)"
          class="relative"
        >
          <button
            type="button"
            class="flex max-w-48 items-center gap-2 rounded-xl border border-n-weak bg-n-background px-3 py-2 text-sm transition-colors hover:bg-n-alpha-2"
            aria-haspopup="listbox"
            :aria-expanded="presenceDropdownOpen"
            :title="presenceName"
            @click="presenceDropdownOpen = !presenceDropdownOpen"
          >
            <span
              class="size-2.5 flex-shrink-0 rounded-full"
              :style="{ backgroundColor: presenceColor }"
              aria-hidden="true"
            />
            <span class="hidden truncate text-n-slate-11 lg:block">
              {{ presenceName }}
            </span>
            <span
              class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-9"
              aria-hidden="true"
            />
          </button>
          <div
            v-if="presenceDropdownOpen"
            class="absolute right-0 top-full z-[70] mt-2 min-w-52 overflow-hidden rounded-xl border border-n-weak bg-n-surface-2 py-1 shadow-lg"
            role="listbox"
          >
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors hover:bg-n-alpha-2"
              :class="
                !currentAppState
                  ? 'font-semibold text-n-slate-12'
                  : 'text-n-slate-11'
              "
              role="option"
              :aria-selected="!currentAppState"
              @click="setPresence(null)"
            >
              <span class="size-2 rounded-full bg-green-500" />
              {{
                currentAppState
                  ? t('JABVOX_MANAGEMENT_STATES.APP_STATES.ACTIVE_RETURN')
                  : t('JABVOX_MANAGEMENT_STATES.APP_STATES.ACTIVE_DEFAULT')
              }}
            </button>
            <button
              v-for="state in appStatesForPresence"
              :key="state.id"
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors hover:bg-n-alpha-2"
              :class="
                currentAppState?.id === state.id
                  ? 'font-semibold text-n-slate-12'
                  : 'text-n-slate-11'
              "
              role="option"
              :aria-selected="currentAppState?.id === state.id"
              @click="setPresence(state.id)"
            >
              <span
                class="size-2 flex-shrink-0 rounded-full"
                :style="{ backgroundColor: state.color }"
              />
              {{ state.name }}
            </button>
          </div>
        </div>
        <SidebarQuickPreferences />
        <SidebarNotificationBell
          class="size-9 rounded-xl border border-n-weak bg-n-background"
          @open-notification-panel="
            router.push({ name: 'notifications_index' })
          "
        />
      </div>
    </div>
  </header>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      {
        ignore: [
          '#mobile-sidebar-launcher',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-gradient-to-b from-[#DAEBDB] to-[#A8D5D3] flex flex-col text-sm pb-px absolute top-0 bottom-0 ltr:left-0 rtl:right-0 h-auto z-40 w-[200px] md:w-auto md:relative md:mt-16 md:h-[calc(100%-4rem)] md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 ltr:border-r rtl:border-l border-[#8FC4C2]"
    :class="[
      {
        'shadow-lg md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'transition-transform duration-200 ease-out md:transition-[width]':
          !isResizing,
      },
    ]"
    :style="isMobile ? undefined : { width: `${sidebarWidth}px` }"
  >
    <section v-if="isMobile" class="grid mt-1 mb-4 gap-2">
      <div class="flex min-w-0 items-center gap-2 px-2">
        <img
          :src="JABVOX_LOGO_URL"
          alt="Jabvox"
          class="h-10 w-auto max-w-[112px] flex-shrink-0 object-contain"
        />
        <div class="h-6 w-px flex-shrink-0 bg-[#5B9690]/50" />
        <SidebarAccountSwitcher
          class="min-w-0 flex-1"
          @show-create-account-modal="emit('showCreateAccountModal')"
        />
        <SidebarQuickPreferences />
        <SidebarNotificationBell
          class="size-9 flex-shrink-0 rounded-xl border border-[#8FC4C2]/60 bg-white/40"
          @open-notification-panel="
            router.push({ name: 'notifications_index' })
          "
        />
      </div>
      <div v-if="isSaldoEnabled" class="px-2">
        <div
          class="px-2 py-1 rounded-lg bg-n-alpha-2 flex items-center justify-between text-xs"
        >
          <span class="text-n-slate-11">{{
            t('JABVOX_SALDO.HEADER.LABEL')
          }}</span>
          <span class="font-medium" :class="saldoBalanceColor">{{
            saldoLabel
          }}</span>
        </div>
      </div>
      <div v-if="canViewAiBalance" class="px-2">
        <div
          class="px-2 py-1 rounded-lg bg-n-alpha-2 flex items-center justify-between text-xs"
        >
          <span class="text-n-slate-11">{{
            t('SIDEBAR.JABVOX_AI_BUDGET')
          }}</span>
          <span class="font-medium" :class="aiBalanceColor">
            {{ aiBalanceLabel }}
          </span>
        </div>
      </div>
      <div
        v-if="isMobile"
        v-on-click-outside="() => (presenceDropdownOpen = false)"
        class="px-2 relative"
      >
        <button
          class="w-full px-2 py-1 rounded-lg bg-n-alpha-2 flex items-center gap-2 text-xs hover:bg-n-alpha-3 transition-colors"
          @click="presenceDropdownOpen = !presenceDropdownOpen"
        >
          <span
            class="w-2 h-2 rounded-full flex-shrink-0"
            :style="{ backgroundColor: presenceColor }"
          />
          <span class="flex-1 text-left text-n-slate-11">{{
            presenceName
          }}</span>
          <span
            class="i-lucide-chevrons-up-down w-3 h-3 text-n-slate-9 flex-shrink-0"
          />
        </button>
        <div
          v-if="presenceDropdownOpen"
          class="absolute top-full left-0 right-0 mt-1 bg-n-surface-2 border border-n-weak rounded-xl shadow-lg overflow-hidden z-50"
        >
          <button
            class="w-full flex items-center gap-2 px-3 py-2 text-xs transition-colors hover:bg-n-alpha-2"
            :class="
              !currentAppState
                ? 'font-semibold text-n-slate-12'
                : 'text-n-slate-11'
            "
            @click="setPresence(null)"
          >
            <span class="w-2 h-2 rounded-full bg-green-500 flex-shrink-0" />
            {{
              currentAppState
                ? t('JABVOX_MANAGEMENT_STATES.APP_STATES.ACTIVE_RETURN')
                : t('JABVOX_MANAGEMENT_STATES.APP_STATES.ACTIVE_DEFAULT')
            }}
          </button>
          <button
            v-for="state in appStatesForPresence"
            :key="state.id"
            class="w-full flex items-center gap-2 px-3 py-2 text-xs transition-colors hover:bg-n-alpha-2"
            :class="
              currentAppState?.id === state.id
                ? 'font-semibold text-n-slate-12'
                : 'text-n-slate-11'
            "
            @click="setPresence(state.id)"
          >
            <span
              class="w-2 h-2 rounded-full flex-shrink-0"
              :style="{ backgroundColor: state.color }"
            />
            {{ state.name }}
          </button>
        </div>
      </div>
    </section>
    <nav
      class="grid overflow-y-scroll flex-grow gap-2 pb-5 no-scrollbar min-w-0"
      :class="isEffectivelyCollapsed ? 'px-1' : 'px-2'"
    >
      <ul
        class="flex flex-col gap-1 m-0 list-none min-w-0"
        :class="{ 'items-center': isEffectivelyCollapsed }"
      >
        <SidebarGroup
          v-for="item in menuItems"
          :key="item.name"
          v-bind="item"
        />
      </ul>
    </nav>
    <section
      class="flex relative flex-col flex-shrink-0 gap-1 justify-between items-center"
    >
      <div
        class="pointer-events-none absolute inset-x-0 -top-[1.938rem] h-8 bg-gradient-to-t from-[#A8D5D3] to-transparent"
      />
      <SidebarChangelogCard
        v-if="
          isOnJabvoxCloud &&
          !isACustomBrandedInstance &&
          !isEffectivelyCollapsed
        "
      />
      <SidebarChangelogButton
        v-if="
          isOnJabvoxCloud && !isACustomBrandedInstance && isEffectivelyCollapsed
        "
      />
      <div
        class="px-1 py-1.5 flex-shrink-0 flex w-full z-50 gap-2 items-center border-t border-[#8FC4C2]/60 shadow-[0px_-2px_4px_0px_rgba(27,28,29,0.02)]"
        :class="isEffectivelyCollapsed ? 'justify-center' : 'justify-between'"
      >
        <SidebarProfileMenu
          :is-collapsed="isEffectivelyCollapsed"
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        />
      </div>
    </section>
    <!-- Resize Handle (desktop only) -->
    <div
      class="hidden md:block absolute top-0 h-full w-1 cursor-col-resize z-40 ltr:right-0 rtl:left-0 group"
      @mousedown="onResizeStart"
      @touchstart="onResizeStart"
      @dblclick="onResizeHandleDoubleClick"
    >
      <div
        class="absolute top-0 h-full w-px ltr:right-0 rtl:left-0 bg-transparent group-hover:bg-n-brand transition-colors"
        :class="{ 'bg-n-brand': isResizing }"
      />
    </div>
  </aside>
</template>
