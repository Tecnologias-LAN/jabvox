<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const metrics = useMapGetter('jabvoxTickets/getMetrics');

const fmtInt = v => (v == null ? '0' : Number(v).toLocaleString());

const cards = computed(() => {
  const m = metrics.value;
  if (!m) return [];
  const total = m.totals || {};
  return [
    {
      key: 'total',
      label: t('JABVOX_TICKETS.METRICS.TOTAL'),
      value: fmtInt(total.total),
    },
    {
      key: 'open',
      label: t('JABVOX_TICKETS.METRICS.OPEN'),
      value: fmtInt(total.open),
    },
    {
      key: 'resolved',
      label: t('JABVOX_TICKETS.METRICS.RESOLVED'),
      value: fmtInt(total.resolved),
    },
    {
      key: 'closed',
      label: t('JABVOX_TICKETS.METRICS.CLOSED'),
      value: fmtInt(total.closed),
    },
    {
      key: 'overdue',
      label: t('JABVOX_TICKETS.METRICS.OVERDUE'),
      value: fmtInt(total.overdue),
      danger: (total.overdue || 0) > 0,
    },
    {
      key: 'sla',
      label: t('JABVOX_TICKETS.METRICS.SLA'),
      value: `${m.sla_compliance_pct ?? 0}%`,
      positive: true,
    },
    {
      key: 'avg',
      label: t('JABVOX_TICKETS.METRICS.AVG_RESOLUTION'),
      value: `${m.avg_resolution_minutes ?? 0} min`,
    },
    {
      key: 'sat',
      label: t('JABVOX_TICKETS.METRICS.SATISFACTION'),
      value: m.avg_satisfaction ? `${m.avg_satisfaction}/5` : '—',
    },
  ];
});

const distributions = computed(() => {
  const m = metrics.value;
  if (!m) return [];
  return [
    {
      key: 'status',
      title: t('JABVOX_TICKETS.METRICS.BY_STATUS'),
      data: m.by_status,
      ns: 'STATUS',
    },
    {
      key: 'type',
      title: t('JABVOX_TICKETS.METRICS.BY_TYPE'),
      data: m.by_type,
      ns: 'TYPE',
    },
    {
      key: 'priority',
      title: t('JABVOX_TICKETS.METRICS.BY_PRIORITY'),
      data: m.by_priority,
      ns: 'PRIORITY',
    },
    {
      key: 'category',
      title: t('JABVOX_TICKETS.METRICS.BY_CATEGORY'),
      data: m.by_category,
      ns: null,
    },
    {
      key: 'agent',
      title: t('JABVOX_TICKETS.METRICS.BY_AGENT'),
      data: m.by_agent,
      ns: null,
    },
  ];
});

const rowLabel = (dist, key) =>
  dist.ns ? t(`JABVOX_TICKETS.${dist.ns}.${(key || '').toUpperCase()}`) : key;

const goBack = () => router.push({ name: 'jabvox_tickets_index' });

onMounted(() => store.dispatch('jabvoxTickets/fetchMetrics'));
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <div>
        <button class="text-xs text-n-slate-10 hover:underline" @click="goBack">
          {{ `← ${t('JABVOX_TICKETS.DETAIL.BACK')}` }}
        </button>
        <h1 class="text-lg font-semibold text-n-slate-12 mt-1">
          {{ t('JABVOX_TICKETS.METRICS.TITLE') }}
        </h1>
      </div>
    </header>

    <div v-if="!metrics" class="flex items-center justify-center py-16">
      <Spinner :size="24" />
    </div>
    <div v-else class="flex-1 overflow-y-auto px-6 py-4 flex flex-col gap-6">
      <!-- KPIs -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div
          v-for="card in cards"
          :key="card.key"
          class="rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 shadow-sm"
        >
          <div class="text-xs text-n-slate-11">{{ card.label }}</div>
          <div
            class="text-2xl font-semibold mt-1"
            :class="[
              card.positive ? 'text-n-teal-11' : '',
              card.danger ? 'text-n-ruby-11' : 'text-n-slate-12',
            ]"
          >
            {{ card.value }}
          </div>
        </div>
      </div>

      <!-- Distribuciones -->
      <div class="grid md:grid-cols-2 gap-4">
        <div
          v-for="dist in distributions"
          :key="dist.key"
          class="rounded-lg border border-n-weak p-4"
        >
          <h4 class="text-sm font-medium text-n-slate-12 mb-2">
            {{ dist.title }}
          </h4>
          <ul class="flex flex-col gap-1 text-sm">
            <li
              v-for="(count, key) in dist.data"
              :key="key"
              class="flex justify-between text-n-slate-11"
            >
              <span>{{ rowLabel(dist, key) }}</span>
              <span class="text-n-slate-12 tabular-nums">{{
                fmtInt(count)
              }}</span>
            </li>
            <li
              v-if="!dist.data || !Object.keys(dist.data).length"
              class="text-n-slate-9"
            >
              {{ t('JABVOX_TICKETS.METRICS.NO_DATA') }}
            </li>
          </ul>
        </div>
      </div>
    </div>
  </div>
</template>
