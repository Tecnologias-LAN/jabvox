<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';

const { t } = useI18n();
const route = useRoute();
const getters = useStoreGetters();
const capabilities = useAnalyticsCapabilitiesStore();

const accountId = computed(() => getters.getCurrentAccountId.value);

const tabs = computed(() => {
  const items = [
    {
      key: 'data-sources',
      label: t('JABVOX_ANALYTICS.NAV.DATA_SOURCES'),
      icon: 'i-lucide-database',
      routeName: 'jabvox_analytics_data_sources',
      activeOn: [
        'jabvox_analytics_data_sources',
        'jabvox_analytics_ds_tables',
        'jabvox_analytics_ds_viewer',
        'jabvox_analytics_query_builder',
        'jabvox_analytics_sql',
      ],
    },
    {
      key: 'dashboards',
      label: t('JABVOX_ANALYTICS.NAV.DASHBOARDS'),
      icon: 'i-lucide-layout-dashboard',
      routeName: 'jabvox_analytics_dashboards',
      activeOn: [
        'jabvox_analytics_dashboards',
        'jabvox_analytics_dashboard_show',
      ],
    },
  ];
  if (capabilities.isAdmin) {
    items.push({
      key: 'permissions',
      label: t('JABVOX_ANALYTICS.NAV.PERMISSIONS'),
      icon: 'i-lucide-shield-check',
      routeName: 'jabvox_analytics_permissions',
      activeOn: ['jabvox_analytics_permissions'],
    });
  }
  return items;
});

const isActive = tab => tab.activeOn.includes(route.name);

onMounted(() => {
  if (!capabilities.loaded) capabilities.fetch();
});
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <nav
      class="flex items-center gap-1 px-4 border-b border-n-weak shrink-0 h-14"
    >
      <router-link
        v-for="tab in tabs"
        :key="tab.key"
        :to="{ name: tab.routeName, params: { accountId } }"
        class="flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg transition-colors"
        :class="
          isActive(tab)
            ? 'bg-n-alpha-2 text-n-slate-12'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
      >
        <span :class="tab.icon" class="size-4" />
        {{ tab.label }}
      </router-link>
    </nav>
    <div class="flex-1 min-h-0 p-4 overflow-auto">
      <router-view />
    </div>
  </div>
</template>
