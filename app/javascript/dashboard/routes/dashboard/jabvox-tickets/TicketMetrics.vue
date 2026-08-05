<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BaseChart from 'dashboard/routes/dashboard/jabvox-analytics/dashboards/widgets/BaseChart.vue';
import KpiCard from './components/KpiCard.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const metrics = useMapGetter('jabvoxTickets/getMetrics');

const fmtInt = v => (v == null ? '0' : Number(v).toLocaleString());

// KPIs destacados con ícono, tono y tooltip explicativo.
const cards = computed(() => {
  const m = metrics.value;
  if (!m) return [];
  const total = m.totals || {};
  return [
    {
      key: 'total',
      label: t('JABVOX_TICKETS.METRICS.TOTAL'),
      value: fmtInt(total.total),
      icon: 'i-lucide-ticket',
      tone: 'brand',
      hint: t('JABVOX_TICKETS.METRICS.HINT.TOTAL'),
    },
    {
      key: 'open',
      label: t('JABVOX_TICKETS.METRICS.OPEN'),
      value: fmtInt(total.open),
      icon: 'i-lucide-circle-dot',
      tone: 'blue',
      hint: t('JABVOX_TICKETS.METRICS.HINT.OPEN'),
    },
    {
      key: 'resolved',
      label: t('JABVOX_TICKETS.METRICS.RESOLVED'),
      value: fmtInt(total.resolved),
      icon: 'i-lucide-check-circle-2',
      tone: 'teal',
      hint: t('JABVOX_TICKETS.METRICS.HINT.RESOLVED'),
    },
    {
      key: 'overdue',
      label: t('JABVOX_TICKETS.METRICS.OVERDUE'),
      value: fmtInt(total.overdue),
      icon: 'i-lucide-alarm-clock',
      tone: (total.overdue || 0) > 0 ? 'ruby' : 'slate',
      hint: t('JABVOX_TICKETS.METRICS.HINT.OVERDUE'),
    },
    {
      key: 'sla',
      label: t('JABVOX_TICKETS.METRICS.SLA'),
      value: `${m.sla_compliance_pct ?? 0}%`,
      icon: 'i-lucide-shield-check',
      tone: 'teal',
      hint: t('JABVOX_TICKETS.METRICS.HINT.SLA'),
    },
    {
      key: 'avg',
      label: t('JABVOX_TICKETS.METRICS.AVG_RESOLUTION'),
      value: `${m.avg_resolution_minutes ?? 0} min`,
      icon: 'i-lucide-timer',
      tone: 'amber',
      hint: t('JABVOX_TICKETS.METRICS.HINT.AVG_RESOLUTION'),
    },
    {
      key: 'sat',
      label: t('JABVOX_TICKETS.METRICS.SATISFACTION'),
      value: m.avg_satisfaction ? `${m.avg_satisfaction}/5` : '—',
      icon: 'i-lucide-star',
      tone: 'amber',
      hint: t('JABVOX_TICKETS.METRICS.HINT.SATISFACTION'),
    },
    {
      key: 'closed',
      label: t('JABVOX_TICKETS.METRICS.CLOSED'),
      value: fmtInt(total.closed),
      icon: 'i-lucide-archive',
      tone: 'slate',
      hint: t('JABVOX_TICKETS.METRICS.HINT.CLOSED'),
    },
  ];
});

// Traduce las claves de un mapa de distribución con su namespace i18n.
const labelFor = (ns, key) =>
  ns ? t(`JABVOX_TICKETS.${ns}.${(key || '').toUpperCase()}`) : key;

const entriesOf = obj => Object.entries(obj || {});

// --- Opciones de ECharts (usan BaseChart, theme-aware) ---

// Serie temporal: creados últimos 30 días (línea con área).
const trendOption = computed(() => {
  const data = entriesOf(metrics.value?.created_last_30_days).sort((a, b) =>
    a[0] < b[0] ? -1 : 1
  );
  return {
    grid: { left: 40, right: 16, top: 20, bottom: 30 },
    tooltip: { trigger: 'axis', confine: true },
    xAxis: { type: 'category', data: data.map(d => d[0].slice(5)) },
    yAxis: { type: 'value', minInterval: 1 },
    series: [
      {
        type: 'line',
        smooth: true,
        showSymbol: false,
        areaStyle: { opacity: 0.15 },
        lineStyle: { width: 2 },
        data: data.map(d => d[1]),
      },
    ],
  };
});

// Barra vertical para una distribución con namespace i18n (estado/tipo/prioridad).
const barOption = (map, ns) => {
  const entries = entriesOf(map);
  return {
    grid: { left: 40, right: 16, top: 20, bottom: 40 },
    tooltip: { trigger: 'axis', confine: true },
    xAxis: {
      type: 'category',
      data: entries.map(([k]) => labelFor(ns, k)),
      axisLabel: { interval: 0, rotate: entries.length > 4 ? 25 : 0 },
    },
    yAxis: { type: 'value', minInterval: 1 },
    series: [
      {
        type: 'bar',
        barMaxWidth: 40,
        itemStyle: { borderRadius: [6, 6, 0, 0] },
        data: entries.map(([, v]) => v),
      },
    ],
  };
};

// Barra horizontal para agente / tema (nombres largos).
const hbarOption = map => {
  const entries = entriesOf(map).sort((a, b) => a[1] - b[1]);
  return {
    grid: { left: 90, right: 24, top: 10, bottom: 20 },
    tooltip: { trigger: 'axis', confine: true },
    xAxis: { type: 'value', minInterval: 1 },
    yAxis: { type: 'category', data: entries.map(([k]) => k) },
    series: [
      {
        type: 'bar',
        barMaxWidth: 22,
        itemStyle: { borderRadius: [0, 6, 6, 0] },
        data: entries.map(([, v]) => v),
      },
    ],
  };
};

const statusOption = computed(() =>
  barOption(metrics.value?.by_status, 'STATUS')
);
const typeOption = computed(() => barOption(metrics.value?.by_type, 'TYPE'));
const priorityOption = computed(() =>
  barOption(metrics.value?.by_priority, 'PRIORITY')
);
const categoryOption = computed(() => hbarOption(metrics.value?.by_category));
const agentOption = computed(() => hbarOption(metrics.value?.by_agent));

const hasData = obj => Object.keys(obj || {}).length > 0;

const goBack = () => router.push({ name: 'jabvox_tickets_index' });

onMounted(() => store.dispatch('jabvoxTickets/fetchMetrics'));
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between px-4 sm:px-6 py-4 border-b border-n-weak"
    >
      <div>
        <button
          class="inline-flex items-center gap-1 text-xs text-n-slate-10 hover:text-n-slate-12 transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand rounded"
          @click="goBack"
        >
          <span class="i-lucide-arrow-left w-3.5 h-3.5" aria-hidden="true" />
          {{ t('JABVOX_TICKETS.DETAIL.BACK') }}
        </button>
        <h1 class="text-lg font-semibold text-n-slate-12 mt-1">
          {{ t('JABVOX_TICKETS.METRICS.TITLE') }}
        </h1>
      </div>
    </header>

    <div v-if="!metrics" class="flex items-center justify-center py-16">
      <Spinner :size="24" />
    </div>

    <div
      v-else
      class="flex-1 overflow-y-auto px-4 sm:px-6 py-5 flex flex-col gap-6"
    >
      <!-- KPIs -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <KpiCard
          v-for="card in cards"
          :key="card.key"
          :label="card.label"
          :value="card.value"
          :icon="card.icon"
          :tone="card.tone"
          :hint="card.hint"
        />
      </div>

      <!-- Tendencia 30 días -->
      <section
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
      >
        <h4
          class="flex items-center gap-2 text-sm font-semibold text-n-slate-12 mb-3"
          :title="t('JABVOX_TICKETS.METRICS.HINT.TREND')"
        >
          <span
            class="i-lucide-trending-up w-4 h-4 text-n-slate-10"
            aria-hidden="true"
          />
          {{ t('JABVOX_TICKETS.METRICS.TREND') }}
        </h4>
        <div class="h-56">
          <BaseChart
            v-if="hasData(metrics.created_last_30_days)"
            :option="trendOption"
          />
          <p v-else class="text-sm text-n-slate-9 text-center py-16">
            {{ t('JABVOX_TICKETS.METRICS.NO_DATA') }}
          </p>
        </div>
      </section>

      <!-- Distribuciones -->
      <div class="grid md:grid-cols-2 xl:grid-cols-3 gap-4">
        <section
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
        >
          <h4 class="text-sm font-semibold text-n-slate-12 mb-3">
            {{ t('JABVOX_TICKETS.METRICS.BY_STATUS') }}
          </h4>
          <div class="h-48">
            <BaseChart
              v-if="hasData(metrics.by_status)"
              :option="statusOption"
            />
            <p v-else class="tk-nodata">
              {{ t('JABVOX_TICKETS.METRICS.NO_DATA') }}
            </p>
          </div>
        </section>

        <section
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
        >
          <h4 class="text-sm font-semibold text-n-slate-12 mb-3">
            {{ t('JABVOX_TICKETS.METRICS.BY_TYPE') }}
          </h4>
          <div class="h-48">
            <BaseChart v-if="hasData(metrics.by_type)" :option="typeOption" />
            <p v-else class="tk-nodata">
              {{ t('JABVOX_TICKETS.METRICS.NO_DATA') }}
            </p>
          </div>
        </section>

        <section
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
        >
          <h4 class="text-sm font-semibold text-n-slate-12 mb-3">
            {{ t('JABVOX_TICKETS.METRICS.BY_PRIORITY') }}
          </h4>
          <div class="h-48">
            <BaseChart
              v-if="hasData(metrics.by_priority)"
              :option="priorityOption"
            />
            <p v-else class="tk-nodata">
              {{ t('JABVOX_TICKETS.METRICS.NO_DATA') }}
            </p>
          </div>
        </section>

        <section
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm md:col-span-2 xl:col-span-1"
        >
          <h4 class="text-sm font-semibold text-n-slate-12 mb-3">
            {{ t('JABVOX_TICKETS.METRICS.BY_CATEGORY') }}
          </h4>
          <div class="h-48">
            <BaseChart
              v-if="hasData(metrics.by_category)"
              :option="categoryOption"
            />
            <p v-else class="tk-nodata">
              {{ t('JABVOX_TICKETS.METRICS.NO_DATA') }}
            </p>
          </div>
        </section>

        <section
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm xl:col-span-2"
        >
          <h4 class="text-sm font-semibold text-n-slate-12 mb-3">
            {{ t('JABVOX_TICKETS.METRICS.BY_AGENT') }}
          </h4>
          <div class="h-48">
            <BaseChart v-if="hasData(metrics.by_agent)" :option="agentOption" />
            <p v-else class="tk-nodata">
              {{ t('JABVOX_TICKETS.METRICS.NO_DATA') }}
            </p>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<style scoped>
.tk-nodata {
  @apply text-sm text-n-slate-9 text-center py-16;
}
</style>
