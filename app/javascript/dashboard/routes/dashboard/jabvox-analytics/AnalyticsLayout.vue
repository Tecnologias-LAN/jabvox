<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';

const { t } = useI18n();
const route = useRoute();
const getters = useStoreGetters();
const capabilities = useAnalyticsCapabilitiesStore();

const accountId = computed(() => getters.getCurrentAccountId.value);
const showNav = ref(false); // mobile drawer

const tabs = computed(() => {
  const items = [
    {
      key: 'overview',
      label: t('JABVOX_ANALYTICS.NAV.OVERVIEW'),
      icon: 'i-lucide-gauge',
      routeName: 'jabvox_analytics_overview',
      activeOn: ['jabvox_analytics_overview', 'jabvox_analytics_index'],
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
      key: 'cross-reports',
      label: t('JABVOX_ANALYTICS.NAV.CROSS_REPORTS'),
      icon: 'i-lucide-combine',
      routeName: 'jabvox_analytics_cross_reports',
      activeOn: [
        'jabvox_analytics_cross_reports',
        'jabvox_analytics_cross_report_new',
        'jabvox_analytics_cross_report_edit',
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

const closeNav = () => {
  showNav.value = false;
};

onMounted(() => {
  if (!capabilities.loaded) capabilities.fetch();
});
</script>

<template>
  <div class="flex w-full h-full bg-n-background relative">
    <!-- Mobile drawer backdrop -->
    <div
      v-if="showNav"
      class="fixed inset-0 z-30 bg-n-alpha-black2 md:hidden"
      @click="closeNav"
    />

    <!-- Analytics sidebar (its own BI identity) -->
    <aside
      class="z-40 w-60 shrink-0 h-full border-r border-n-weak bg-n-solid-1 flex-col md:flex md:static"
      :class="
        showNav ? 'flex fixed inset-y-0 left-0 shadow-xl' : 'hidden md:flex'
      "
    >
      <!-- Brand header -->
      <div
        class="flex items-center gap-2.5 px-4 h-14 border-b border-n-weak shrink-0"
      >
        <span
          class="i-lucide-chart-no-axes-combined size-8 rounded-lg bg-n-brand/15 p-1.5 text-n-brand shrink-0"
        />
        <div class="min-w-0">
          <p class="text-sm font-semibold text-n-slate-12 leading-tight">
            {{ t('JABVOX_ANALYTICS.BRAND') }}
          </p>
          <p class="text-[11px] text-n-slate-10 leading-tight">
            {{ t('JABVOX_ANALYTICS.BRAND_SUB') }}
          </p>
        </div>
      </div>

      <!-- Nav -->
      <nav class="flex-1 min-h-0 overflow-y-auto p-2.5 space-y-1">
        <router-link
          v-for="tab in tabs"
          :key="tab.key"
          :to="{ name: tab.routeName, params: { accountId } }"
          class="flex items-center gap-2.5 px-3 py-2 text-sm font-medium rounded-lg transition-colors"
          :class="
            isActive(tab)
              ? 'bg-n-brand/12 text-n-brand'
              : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
          "
          @click="closeNav"
        >
          <span :class="tab.icon" class="size-4 shrink-0" />
          {{ tab.label }}
        </router-link>
      </nav>
    </aside>

    <!-- Content -->
    <div class="flex-1 min-w-0 h-full flex flex-col">
      <!-- Mobile: open sidebar -->
      <button
        type="button"
        class="md:hidden flex items-center gap-2 shrink-0 px-4 h-12 border-b border-n-weak bg-n-solid-1 text-sm font-medium text-n-slate-11"
        @click="showNav = true"
      >
        <span class="i-lucide-panel-left size-4" />
        {{ t('JABVOX_ANALYTICS.BRAND') }}
      </button>
      <div class="flex-1 min-h-0 p-4 overflow-auto">
        <router-view />
      </div>
    </div>
  </div>
</template>
