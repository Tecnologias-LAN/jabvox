<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStoreGetters } from 'dashboard/composables/store';
import { analyticsDashboardsAPI } from 'dashboard/api/jabvox/analytics';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsLoadingState from '../components/AnalyticsLoadingState.vue';

const { t } = useI18n();
const router = useRouter();
const getters = useStoreGetters();

const accountId = getters.getCurrentAccountId.value;
const loading = ref(true);
const stats = ref({});

// KPI cards — each maps to a real, account-scoped counter from the backend.
const KPIS = [
  {
    key: 'total_dashboards',
    label: 'DASHBOARDS',
    icon: 'i-lucide-layout-dashboard',
    tone: 'brand',
  },
  {
    key: 'total_data_sources',
    label: 'DATA_SOURCES',
    icon: 'i-lucide-database',
    tone: 'blue',
  },
  {
    key: 'data_sources_ok',
    label: 'SOURCES_OK',
    icon: 'i-lucide-plug-zap',
    tone: 'teal',
  },
  {
    key: 'total_widgets',
    label: 'WIDGETS',
    icon: 'i-lucide-shapes',
    tone: 'iris',
  },
  {
    key: 'shared_dashboards',
    label: 'SHARED',
    icon: 'i-lucide-share-2',
    tone: 'amber',
  },
  {
    key: 'users_with_access',
    label: 'USERS_ACCESS',
    icon: 'i-lucide-users',
    tone: 'blue',
  },
  {
    key: 'actions_today',
    label: 'ACTIONS_TODAY',
    icon: 'i-lucide-activity',
    tone: 'teal',
  },
  {
    key: 'total_exports',
    label: 'EXPORTS',
    icon: 'i-lucide-download',
    tone: 'iris',
  },
];

const TONE = {
  brand: 'bg-n-brand/12 text-n-brand',
  blue: 'bg-n-blue-3 text-n-blue-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
};

const QUICK = [
  {
    label: 'GO_DASHBOARDS',
    icon: 'i-lucide-layout-dashboard',
    route: 'jabvox_analytics_dashboards',
  },
  {
    label: 'GO_SOURCES',
    icon: 'i-lucide-database',
    route: 'jabvox_analytics_data_sources',
  },
  {
    label: 'GO_PERMISSIONS',
    icon: 'i-lucide-shield-check',
    route: 'jabvox_analytics_permissions',
  },
];

const go = name => router.push({ name, params: { accountId } });

onMounted(async () => {
  try {
    const { data } = await analyticsDashboardsAPI.overviewStats();
    stats.value = data;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div>
    <AnalyticsPageHeader :title="t('JABVOX_ANALYTICS.OVERVIEW.TITLE')">
      <template #actions>
        <span class="text-sm text-n-slate-10 hidden sm:inline">
          {{ t('JABVOX_ANALYTICS.OVERVIEW.SUBTITLE') }}
        </span>
      </template>
    </AnalyticsPageHeader>

    <AnalyticsLoadingState v-if="loading" />

    <template v-else>
      <!-- KPI grid -->
      <div
        class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-4"
      >
        <div
          v-for="kpi in KPIS"
          :key="kpi.key"
          class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm transition-all hover:shadow-md hover:-translate-y-0.5"
        >
          <span
            class="flex items-center justify-center size-10 rounded-xl shrink-0"
            :class="TONE[kpi.tone]"
          >
            <span :class="kpi.icon" class="size-5" />
          </span>
          <div class="min-w-0">
            <p
              class="text-2xl font-semibold text-n-slate-12 tabular-nums leading-tight"
            >
              {{ stats[kpi.key] ?? 0 }}
            </p>
            <p class="text-xs text-n-slate-11 truncate">
              {{ t(`JABVOX_ANALYTICS.OVERVIEW.${kpi.label}`) }}
            </p>
          </div>
        </div>
      </div>

      <!-- Quick access -->
      <div class="mt-8">
        <p
          class="mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_ANALYTICS.OVERVIEW.QUICK') }}
        </p>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <button
            v-for="q in QUICK"
            :key="q.route"
            type="button"
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 text-left shadow-sm transition-all hover:border-n-brand/40 hover:shadow-md"
            @click="go(q.route)"
          >
            <span
              class="flex items-center justify-center size-9 rounded-lg bg-n-alpha-2 text-n-brand shrink-0"
            >
              <span :class="q.icon" class="size-4" />
            </span>
            <span class="text-sm font-medium text-n-slate-12">
              {{ t(`JABVOX_ANALYTICS.OVERVIEW.${q.label}`) }}
            </span>
            <span class="i-lucide-arrow-right size-4 text-n-slate-9 ml-auto" />
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
