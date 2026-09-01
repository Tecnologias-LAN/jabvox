<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { METRIC_BY_KEY } from './reportMetrics.js';
import MetricFilters from './components/MetricFilters.vue';
import TotalsTable from './components/TotalsTable.vue';
import ReportTable from './components/ReportTable.vue';
import ReportPagination from './components/ReportPagination.vue';

// Per-agent drill-down opened from the agents report. Its own route/URL
// (shareable/reloadable): metric, agent, date range, metric-specific filters,
// order and page size all live in the query string. Shows metric filters, a
// totals breakdown (respecting filters) and the paginated records table.
const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const metricKey = computed(() => route.params.metricKey);
const metric = computed(() => METRIC_BY_KEY[metricKey.value]);
const agentName = computed(() => route.query.agent_name || null);

const records = useMapGetter('jabvoxReportsAnalytics/getRecords');
const recordsMeta = useMapGetter('jabvoxReportsAnalytics/getRecordsMeta');
const breakdown = useMapGetter('jabvoxReportsAnalytics/getBreakdown');
const uiFlags = useMapGetter('jabvoxReportsAnalytics/getAnalyticsUIFlags');

const perPage = computed(() => Number(route.query.per_page) || 25);
const orderDir = computed(() => route.query.order_dir || 'desc');

// The metric-specific filter keys we persist in the URL.
const METRIC_FILTER_KEYS = [
  'status',
  'management_state_id',
  'doc_type',
  'product_id',
  'call_status',
];

function pickMetricFilters(query) {
  const out = {};
  METRIC_FILTER_KEYS.forEach(k => {
    if (query[k] !== undefined && query[k] !== '') out[k] = query[k];
  });
  return out;
}

// Editable local state committed to the URL on "Buscar".
const dateFrom = ref(route.query.from || '');
const dateTo = ref(route.query.to || '');
const filterValues = ref(pickMetricFilters(route.query));

// Build the API params from the URL (agent, range and metric filters).
const apiParams = () => {
  const p = { preset: 'custom' };
  if (route.query.from) p.from = route.query.from;
  if (route.query.to) p.to = route.query.to;
  if (route.query.agent_ids) p.agent_ids = [route.query.agent_ids];
  METRIC_FILTER_KEYS.forEach(k => {
    if (route.query[k] !== undefined && route.query[k] !== '') {
      // status is an array param on the backend.
      p[k] = k === 'status' ? [route.query[k]] : route.query[k];
    }
  });
  return p;
};

const loadPage = (append = false) => {
  if (!metric.value) return;
  const cursor = append ? recordsMeta.value?.next_cursor : undefined;
  if (append && !cursor) return;
  store.dispatch('jabvoxReportsAnalytics/fetchRecords', {
    metricKey: metricKey.value,
    params: {
      ...apiParams(),
      per_page: perPage.value,
      order_dir: orderDir.value,
      ...(cursor ? { cursor } : {}),
    },
    append,
  });
};

const loadBreakdown = () => {
  if (!metric.value) return;
  store.dispatch('jabvoxReportsAnalytics/fetchBreakdown', {
    metricKey: metricKey.value,
    params: apiParams(),
  });
};

// Reload records + breakdown whenever anything that affects the query changes.
watch(
  () => [
    metricKey.value,
    route.query.from,
    route.query.to,
    route.query.agent_ids,
    ...METRIC_FILTER_KEYS.map(k => route.query[k]),
    perPage.value,
    orderDir.value,
  ],
  () => {
    loadPage(false);
    loadBreakdown();
  },
  { immediate: true }
);

// Keep local editable state in sync if the URL changes externally.
watch(
  () => route.query,
  q => {
    dateFrom.value = q.from || '';
    dateTo.value = q.to || '';
    filterValues.value = pickMetricFilters(q);
  }
);

const applyFilters = () => {
  const query = { ...route.query, preset: 'custom' };
  if (dateFrom.value) query.from = dateFrom.value;
  else delete query.from;
  if (dateTo.value) query.to = dateTo.value;
  else delete query.to;
  METRIC_FILTER_KEYS.forEach(k => {
    if (filterValues.value[k]) query[k] = filterValues.value[k];
    else delete query[k];
  });
  router.replace({ query });
};

const resetFilters = () => {
  dateFrom.value = '';
  dateTo.value = '';
  filterValues.value = {};
  const query = { ...route.query };
  ['from', 'to', ...METRIC_FILTER_KEYS].forEach(k => delete query[k]);
  router.replace({ query });
};

const setPerPage = size =>
  router.replace({ query: { ...route.query, per_page: size } });

const onSort = () => {
  const next = orderDir.value === 'desc' ? 'asc' : 'desc';
  router.replace({ query: { ...route.query, order_dir: next } });
};

const backToReport = () => {
  const query = { tab: 'agents' };
  if (route.query.from) query.from = route.query.from;
  if (route.query.to) query.to = route.query.to;
  router.push({ name: 'jabvox_reports_index', query });
};
</script>

<template>
  <div v-if="metric" class="flex flex-col gap-5">
    <!-- Heading + back -->
    <div class="flex items-center gap-3">
      <button
        type="button"
        class="flex items-center gap-1.5 rounded-lg border border-n-weak px-2.5 py-1.5 text-sm text-n-slate-11 hover:bg-n-alpha-1"
        @click="backToReport"
      >
        <span class="i-lucide-arrow-left size-4" />
        {{ t('JABVOX_REPORTS.ANALYTICS.BACK') }}
      </button>
      <h2 class="flex items-center gap-2 text-lg font-semibold text-n-slate-12">
        <span class="size-5" :class="[metric.icon, metric.accent]" />
        {{ metric.label }}
        <span
          v-if="agentName"
          class="inline-flex items-center gap-1 rounded-full bg-n-brand/10 px-2.5 py-0.5 text-sm font-medium text-n-brand"
        >
          <span class="i-lucide-user size-3.5" />
          {{ agentName }}
        </span>
      </h2>
    </div>

    <!-- Metric-specific filters + date range -->
    <MetricFilters
      :filters-config="breakdown?.filters_config || []"
      :filter-options="breakdown?.filter_options || {}"
      :values="filterValues"
      :date-from="dateFrom"
      :date-to="dateTo"
      :loading="uiFlags.isFetchingRecords"
      @update:values="filterValues = $event"
      @update:date-from="dateFrom = $event"
      @update:date-to="dateTo = $event"
      @apply="applyFilters"
      @reset="resetFilters"
    />

    <!-- Totals breakdown (respects the active filters) -->
    <TotalsTable
      :total="breakdown?.total || 0"
      :rows="breakdown?.rows || []"
      :label="breakdown?.breakdown_label || ''"
      :loading="uiFlags.isFetchingBreakdown"
    />

    <!-- Records table -->
    <ReportTable
      :columns="metric.columns"
      :rows="records"
      :loading="uiFlags.isFetchingRecords"
      :error="uiFlags.recordsError"
      :order-dir="orderDir"
      @sort="onSort"
      @retry="loadPage(false)"
    />

    <ReportPagination
      :per-page="perPage"
      :total-count="recordsMeta?.total_count || 0"
      :total-is-approx="recordsMeta?.total_is_approx || false"
      :loaded-count="records.length"
      :has-more="recordsMeta?.has_more || false"
      :loading="uiFlags.isFetchingRecords"
      @update:per-page="setPerPage"
      @load-more="loadPage(true)"
    />
  </div>

  <div v-else class="py-12 text-center text-sm text-n-slate-10">
    {{ t('JABVOX_REPORTS.ANALYTICS.UNKNOWN_METRIC') }}
    <button class="underline" @click="backToReport">
      {{ t('JABVOX_REPORTS.ANALYTICS.BACK') }}
    </button>
  </div>
</template>
