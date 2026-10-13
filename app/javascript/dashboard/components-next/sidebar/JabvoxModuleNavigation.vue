<script setup>
import { computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useJabvoxPermissions } from 'dashboard/composables/useJabvoxPermissions';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  SIDEBAR_SORT_SECTIONS,
  getSidebarSortOptions,
  resolveSidebarSort,
  sortSidebarItems,
} from 'dashboard/helper/sidebarSort';
import SidebarSortMenu from './SidebarSortMenu.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import {
  createJabvoxModuleNavigation,
  isJabvoxNavigationRouteAllowed,
} from './jabvoxModuleNavigation';
import {
  createJabvoxSettingsGroups,
  getJabvoxSettingsCategoryLabels,
} from './jabvoxSettingsNavigation';

const props = defineProps({
  settingsItems: {
    type: Array,
    default: () => [],
  },
});

const UNREAD_COUNT_LIMIT = '99+';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const { accountScopedRoute, isOnJabvoxCloud } = useAccount();
const { isEnterprise } = useConfig();
const { shouldShow } = usePolicy();
const { jabvoxCan } = useJabvoxPermissions();
const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');
const isFeatureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const teams = useMapGetter('teams/getMyTeams');
const folders = useMapGetter('customViews/getConversationCustomViews');
const getInboxUnreadCount = useMapGetter(
  'conversationUnreadCounts/getInboxUnreadCount'
);
const getLabelUnreadCount = useMapGetter(
  'conversationUnreadCounts/getLabelUnreadCount'
);
const getTeamUnreadCount = useMapGetter(
  'conversationUnreadCounts/getTeamUnreadCount'
);
const getFolderUnreadCount = useMapGetter(
  'conversationUnreadCounts/getFolderUnreadCount'
);
const allUnreadCount = useMapGetter(
  'conversationUnreadCounts/getAllUnreadCount'
);
const mentionsUnreadCount = useMapGetter(
  'conversationUnreadCounts/getMentionsUnreadCount'
);
const participatingUnreadCount = useMapGetter(
  'conversationUnreadCounts/getParticipatingUnreadCount'
);
const unattendedUnreadCount = useMapGetter(
  'conversationUnreadCounts/getUnattendedUnreadCount'
);
const internalChatUnreadCount = useMapGetter(
  'jabvoxInternalChat/getUnreadTotal'
);
const getSidebarSectionSort = useMapGetter(
  'sidebarSortPreferences/getSectionSort'
);

// Garantiza que las listas de Etiquetas, Canales, Equipos y Carpetas estén cargadas:
// esta barra de tabs las LEE de la store (useMapGetter), pero quien las carga es el
// Sidebar lateral. Si por orden de montaje o cuenta recién cambiada aún no están, los
// submenús saldrían vacíos. Las pedimos nosotros también (idempotente; el cache evita
// doble fetch). No vacía nada: solo dispara los get si hace falta.
const ensureConversationMenusLoaded = () => {
  if (!accountId.value) return;
  if (!inboxes.value?.length) store.dispatch('inboxes/get');
  if (!labels.value?.length) store.dispatch('labels/get');
  if (!folders.value?.length) store.dispatch('customViews/get', 'conversation');
  if (!teams.value?.length) store.dispatch('teams/get');
};

onMounted(ensureConversationMenusLoaded);
watch(accountId, ensureConversationMenusLoaded);

const hasFeature = flag => isFeatureEnabled.value(accountId.value, flag);
const hasConversationUnreadCounts = computed(() =>
  hasFeature(FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS)
);
const hasFilteredUnreadCounts = computed(
  () =>
    hasConversationUnreadCounts.value &&
    hasFeature(FEATURE_FLAGS.UNREAD_COUNT_FOR_FILTERS)
);
const isRouteAllowed = to =>
  isJabvoxNavigationRouteAllowed(router, shouldShow, to);

const settingsCategoryLabels = getJabvoxSettingsCategoryLabels(t);
const settingsGroups = computed(() =>
  createJabvoxSettingsGroups({
    settingsItems: props.settingsItems,
    categoryLabels: settingsCategoryLabels,
    isRouteAllowed,
  })
);
const isSettingsRoute = item => {
  if (item.to?.query) {
    const hasMatchingQuery = Object.entries(item.to.query).every(
      ([key, value]) => route.query[key] === value
    );
    if (!hasMatchingQuery) return false;
  }

  if (item.to?.name === route.name || item.activeOn?.includes(route.name)) {
    return true;
  }

  if (!item.to) return false;
  const itemPath = router.resolve(item.to).path;
  return route.path === itemPath || route.path.startsWith(`${itemPath}/`);
};
const activeSettingsGroup = computed(
  () =>
    settingsGroups.value.find(category =>
      category.items.some(isSettingsRoute)
    ) || null
);
const settingsSubTabs = computed(() => activeSettingsGroup.value?.items || []);
const isSettingsTabActive = item => isSettingsRoute(item);

const navigationGroups = computed(() =>
  createJabvoxModuleNavigation({
    t,
    accountScopedRoute,
    hasFeature,
    isRouteAllowed,
    isCallsAvailable: isOnJabvoxCloud.value || isEnterprise,
    canViewJabvoxReports: jabvoxCan('jabvox_reports_view'),
  })
);

const activeGroup = computed(
  () =>
    navigationGroups.value.find(group => group.activeOn.includes(route.name)) ||
    null
);

const isTabActive = tab =>
  tab.activeOn?.includes(route.name) ||
  tab.routeNames?.includes(route.name) ||
  (tab.to && router.resolve(tab.to).path === route.path);

const isTabAllowed = tab => !tab.to || isRouteAllowed(tab.to);

const badgeCount = tab => {
  const counts = {
    all: allUnreadCount.value,
    mentions: mentionsUnreadCount.value,
    participating: participatingUnreadCount.value,
    unattended: unattendedUnreadCount.value,
    'internal-chat': internalChatUnreadCount.value,
  };
  return counts[tab.badgeKey || tab.key] || 0;
};

const hasUnreadCountsForSection = section =>
  section === SIDEBAR_SORT_SECTIONS.FOLDERS
    ? hasFilteredUnreadCounts.value
    : hasConversationUnreadCounts.value;

const sortOptionsFor = section =>
  getSidebarSortOptions(section, {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const activeSortFor = section =>
  resolveSidebarSort(section, getSidebarSectionSort.value(section), {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const sortItems = (items, section, labelKey, unreadCountKey) =>
  sortSidebarItems(items.value, {
    sortBy: activeSortFor(section),
    labelKey,
    unreadCountKey,
  });

const updateSort = (section, sortBy) => {
  store.dispatch('sidebarSortPreferences/setSectionSort', {
    section,
    sortBy,
  });
};

const menuItems = tab => {
  // OJO: un array vacío es truthy en JS. Los tabs dinámicos (labels/channels/folders/teams)
  // traen items: [] por defecto; hay que usar .length, o nunca llegaríamos a sus ramas
  // dinámicas y el submenú saldría siempre vacío ("No items").
  if (tab.items?.length) {
    return tab.items.filter(item => isRouteAllowed(item.to));
  }

  if (tab.key === 'channels') {
    const channels = sortItems(
      inboxes,
      SIDEBAR_SORT_SECTIONS.CHANNELS,
      inbox => inbox.name,
      inbox => getInboxUnreadCount.value(inbox.id)
    ).map(inbox => ({
      key: `channel-${inbox.id}`,
      label: inbox.name,
      to: accountScopedRoute('inbox_dashboard', { inbox_id: inbox.id }),
      badgeCount: getInboxUnreadCount.value(inbox.id),
    }));
    if (hasFeature(FEATURE_FLAGS.INBOX_VIEW)) {
      channels.unshift({
        key: 'inbox-view',
        label: t('SIDEBAR.INBOX_VIEW'),
        to: accountScopedRoute('inbox_view'),
      });
    }
    return channels.filter(
      item => item.key !== 'inbox-view' || isRouteAllowed(item.to)
    );
  }

  if (tab.key === 'labels') {
    return sortItems(
      labels,
      SIDEBAR_SORT_SECTIONS.LABELS,
      label => label.title,
      label => getLabelUnreadCount.value(label.id)
    ).map(label => ({
      key: `label-${label.id}`,
      label: label.title,
      color: label.color,
      to: accountScopedRoute('label_conversations', {
        label: label.title,
      }),
      badgeCount: getLabelUnreadCount.value(label.id),
    }));
  }

  if (tab.key === 'folders') {
    return sortItems(
      folders,
      SIDEBAR_SORT_SECTIONS.FOLDERS,
      folder => folder.name,
      folder => getFolderUnreadCount.value(folder.id)
    )
      .map(folder => ({
        key: `folder-${folder.id}`,
        label: folder.name,
        to: accountScopedRoute('folder_conversations', { id: folder.id }),
        badgeCount: getFolderUnreadCount.value(folder.id),
      }))
      .filter(item => isRouteAllowed(item.to));
  }

  if (tab.key === 'teams') {
    return sortItems(
      teams,
      SIDEBAR_SORT_SECTIONS.TEAMS,
      team => team.name,
      team => getTeamUnreadCount.value(team.id)
    )
      .map(team => ({
        key: `team-${team.id}`,
        label: team.name,
        to: accountScopedRoute('team_conversations', { teamId: team.id }),
        badgeCount: getTeamUnreadCount.value(team.id),
      }))
      .filter(item => isRouteAllowed(item.to));
  }

  return [];
};

const activeTabs = computed(
  () =>
    activeGroup.value?.tabs.filter(
      tab =>
        tab.kind !== 'menu' ||
        menuItems(tab).length > 0 ||
        ['channels', 'labels'].includes(tab.key)
    ) || []
);

const activeSubTabs = computed(() => {
  const parentTab = activeGroup.value?.tabs.find(tab =>
    tab.subTabs?.some(subTab => subTab.activeOn.includes(route.name))
  );

  return parentTab?.subTabs.filter(subTab => isRouteAllowed(subTab.to)) || [];
});

watch(
  [accountId, currentUserId],
  ([currentAccountId, userId]) => {
    if (currentAccountId && userId) {
      store.dispatch('sidebarSortPreferences/initialize');
    }
  },
  { immediate: true }
);
</script>

<template>
  <header
    v-if="activeGroup || activeSettingsGroup"
    class="relative z-20 flex h-14 min-h-14 items-center gap-4 border-b border-n-weak bg-n-surface-1 px-4"
  >
    <span
      class="max-w-36 shrink-0 truncate text-xs font-medium text-n-slate-10"
    >
      {{ activeSettingsGroup?.label || activeGroup.label }}
    </span>
    <span class="h-6 w-px shrink-0 bg-n-weak" />
    <nav
      :aria-label="
        activeSettingsGroup ? t('SIDEBAR.SETTINGS') : activeGroup.label
      "
      class="flex h-full min-w-0 items-center gap-5 overflow-x-auto no-scrollbar"
    >
      <template v-if="activeSettingsGroup">
        <RouterLink
          v-for="tab in settingsSubTabs"
          :key="tab.name"
          :to="tab.to"
          class="relative flex h-full shrink-0 items-center whitespace-nowrap px-0.5 text-sm transition-colors after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:rounded-t"
          :class="
            isSettingsTabActive(tab)
              ? 'font-semibold text-[#15605A] after:bg-[#27958C]'
              : 'text-n-slate-10 hover:text-n-slate-12 after:bg-transparent'
          "
        >
          {{ tab.label }}
        </RouterLink>
      </template>
      <template v-else>
        <template v-for="tab in activeTabs" :key="tab.key">
          <RouterLink
            v-if="tab.to && isTabAllowed(tab)"
            :to="tab.to"
            class="relative flex h-full shrink-0 items-center whitespace-nowrap px-0.5 text-sm transition-colors after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:rounded-t"
            :class="
              isTabActive(tab)
                ? 'font-semibold text-[#15605A] after:bg-[#27958C]'
                : 'text-n-slate-10 hover:text-n-slate-12 after:bg-transparent'
            "
          >
            {{ tab.label }}
            <span
              v-if="badgeCount(tab) > 0"
              class="rounded-full bg-n-brand px-1.5 text-xs font-medium text-white"
            >
              {{ badgeCount(tab) > 99 ? UNREAD_COUNT_LIMIT : badgeCount(tab) }}
            </span>
          </RouterLink>
          <Popover
            v-else-if="tab.kind === 'menu'"
            :key="`${tab.key}-${route.fullPath}`"
            align="start"
            disable-mobile-view
            :show-content-border="false"
            class="flex h-full shrink-0 items-center"
          >
            <template #default="{ isOpen }">
              <button
                type="button"
                class="relative flex h-full items-center gap-1 whitespace-nowrap px-0.5 text-sm transition-colors after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:rounded-t"
                :class="
                  isTabActive(tab) || isOpen
                    ? 'font-semibold text-[#15605A] after:bg-[#27958C]'
                    : 'text-n-slate-10 hover:text-n-slate-12 after:bg-transparent'
                "
                :aria-expanded="isOpen"
                :aria-haspopup="true"
              >
                {{ tab.label }}
                <span
                  class="i-lucide-chevron-down size-3 transition-transform"
                  :class="{ 'rotate-180': isOpen }"
                />
              </button>
            </template>
            <template #content="{ hide }">
              <div
                class="group/sidebar-section max-h-80 min-w-52 overflow-y-auto rounded-xl border border-n-weak bg-n-surface-2 p-1 shadow-lg"
              >
                <div
                  class="flex items-center justify-between gap-2 border-b border-n-weak px-2 py-1"
                >
                  <span
                    class="min-w-0 flex-1 truncate text-xs font-medium text-n-slate-9"
                  >
                    {{ tab.label }}
                  </span>
                  <SidebarSortMenu
                    v-if="menuItems(tab).length > 1"
                    :active-sort="activeSortFor(tab.key)"
                    :options="sortOptionsFor(tab.key)"
                    :open-on-hover="false"
                    @sort="sortBy => updateSort(tab.key, sortBy)"
                  />
                </div>
                <RouterLink
                  v-for="item in menuItems(tab)"
                  :key="item.key"
                  :to="item.to"
                  class="flex min-h-9 items-center gap-2 rounded-lg px-2.5 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  @click="hide"
                >
                  <span
                    v-if="item.color"
                    class="size-2 shrink-0 rounded-sm"
                    :style="{ backgroundColor: item.color }"
                  />
                  <span class="min-w-0 flex-1 truncate">{{ item.label }}</span>
                  <span
                    v-if="item.badgeCount > 0"
                    class="rounded-full bg-n-brand px-1.5 text-xs font-medium text-white"
                  >
                    {{
                      item.badgeCount > 99
                        ? UNREAD_COUNT_LIMIT
                        : item.badgeCount
                    }}
                  </span>
                </RouterLink>
                <span
                  v-if="menuItems(tab).length === 0"
                  class="block px-2.5 py-2 text-sm text-n-slate-9"
                >
                  {{ t('SIDEBAR.NO_ITEMS') }}
                </span>
              </div>
            </template>
          </Popover>
        </template>
      </template>
    </nav>
  </header>
  <nav
    v-if="activeSubTabs.length"
    :aria-label="t('SIDEBAR.JABVOX_REPORTS_MENU')"
    class="flex h-12 min-h-12 items-center gap-5 overflow-x-auto border-b border-n-weak bg-n-surface-1 px-4 ps-8 no-scrollbar"
  >
    <RouterLink
      v-for="tab in activeSubTabs"
      :key="tab.key"
      :to="tab.to"
      class="relative flex h-full shrink-0 items-center whitespace-nowrap px-0.5 text-sm transition-colors after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:rounded-t"
      :class="
        isTabActive(tab)
          ? 'font-semibold text-[#15605A] after:bg-[#27958C]'
          : 'text-n-slate-10 hover:text-n-slate-12 after:bg-transparent'
      "
    >
      {{ tab.label }}
    </RouterLink>
  </nav>
</template>
