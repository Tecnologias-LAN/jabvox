<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import reportsAPI from 'dashboard/api/jabvox/reports';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import FilterBar from '../components/FilterBar.vue';
import KpiCard from '../components/KpiCard.vue';
import AgentCell from '../components/AgentCell.vue';

const { t } = useI18n();

const loading = ref(false);
const agents = ref([]);
const dialerStates = ref([]);
const byStatus = ref({});
const totals = ref({ total_calls: 0, total_answered: 0, total_duration: 0 });
const fetchedAt = ref(null);
const now = ref(Date.now());
let ticker = null;

const filters = ref({ date_from: '', date_to: '' });

const fetch = async () => {
  loading.value = true;
  try {
    const { data } = await reportsAPI.getDialer(filters.value);
    agents.value = data.agents || [];
    dialerStates.value = data.dialer_states || [];
    byStatus.value = data.by_status || {};
    totals.value = {
      total_calls: data.total_calls || 0,
      total_answered: data.total_answered || 0,
      total_duration: data.total_duration || 0,
    };
    fetchedAt.value = Date.now();
    now.value = Date.now();
  } catch {
    agents.value = [];
  } finally {
    loading.value = false;
  }
};

const resetFilters = () => {
  filters.value = { date_from: '', date_to: '' };
  fetch();
};

const byStatusList = computed(() =>
  Object.entries(byStatus.value).map(([k, v]) => ({ key: k, count: v }))
);

const hasAgents = computed(() => agents.value.length > 0);

const elapsedSecs = computed(() =>
  fetchedAt.value ? Math.floor((now.value - fetchedAt.value) / 1000) : 0
);

const ACTIVE_DIALER_STATES = new Set([
  'connected',
  'waiting',
  'in_call',
  'in_comments',
]);

const liveSecs = (agent, stateKey) => {
  const base = agent.state_times?.[stateKey] || 0;
  return agent.current_dialer_state_key === stateKey
    ? base + elapsedSecs.value
    : base;
};

const liveConnectedSecs = agent => {
  const base = Object.entries(agent.state_times || {})
    .filter(([k]) => ACTIVE_DIALER_STATES.has(k))
    .reduce((s, [, v]) => s + (v || 0), 0);
  const isActive =
    agent.current_dialer_state_key &&
    ACTIVE_DIALER_STATES.has(agent.current_dialer_state_key);
  return base + (isActive ? elapsedSecs.value : 0);
};

const liveTotalSecs = agent => {
  const base = Object.values(agent.state_times || {}).reduce(
    (s, v) => s + (v || 0),
    0
  );
  return base + (agent.current_dialer_state_key ? elapsedSecs.value : 0);
};

const formatDuration = (seconds, live = false) => {
  if (!seconds && !live) return '—';
  const s = seconds || 0;
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (live) {
    if (h > 0)
      return `${h}h ${String(m).padStart(2, '0')}m ${String(sec).padStart(2, '0')}s`;
    if (m > 0) return `${m}m ${String(sec).padStart(2, '0')}s`;
    return `${sec}s`;
  }
  if (h > 0) return `${h}h ${m}m`;
  return m > 0 ? `${m}m` : '< 1m';
};

onMounted(() => {
  fetch();
  ticker = setInterval(() => {
    now.value = Date.now();
  }, 1000);
});
onUnmounted(() => clearInterval(ticker));
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -- symbols (—) are universal -->
  <div class="flex flex-col gap-5">
    <!-- Filters -->
    <FilterBar :loading="loading" @apply="fetch" @reset="resetFilters">
      <div class="flex flex-col gap-1.5 w-40">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_REPORTS.COMMON.FILTER_FROM') }}
        </label>
        <Input v-model="filters.date_from" type="date" size="sm" />
      </div>
      <div class="flex flex-col gap-1.5 w-40">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_REPORTS.COMMON.FILTER_TO') }}
        </label>
        <Input v-model="filters.date_to" type="date" size="sm" />
      </div>
    </FilterBar>

    <!-- Summary cards -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <KpiCard
        :label="t('JABVOX_REPORTS.DIALER.STATS.TOTAL_CALLS')"
        :value="totals.total_calls"
      />
      <KpiCard
        :label="t('JABVOX_REPORTS.DIALER.STATS.TOTAL_ANSWERED')"
        :value="totals.total_answered"
        tone="teal"
      />
      <KpiCard
        :label="t('JABVOX_REPORTS.DIALER.STATS.TOTAL_DURATION')"
        tone="brand"
      >
        {{ formatDuration(totals.total_duration) }}
      </KpiCard>
      <div
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm flex flex-col gap-1"
      >
        <p class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_REPORTS.DIALER.STATS.BY_STATUS') }}
        </p>
        <div class="flex flex-wrap gap-1 pt-0.5">
          <span
            v-for="s in byStatusList"
            :key="s.key"
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-n-alpha-2 text-n-slate-12"
          >
            {{ t(`JABVOX_REPORTS.DIALER.STATUS.${s.key}`, s.key) }}
            <span class="font-bold">{{ s.count }}</span>
          </span>
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
      {{ t('JABVOX_REPORTS.COMMON.LOADING') }}
    </div>

    <template v-else-if="hasAgents">
      <!-- Activity table -->
      <div
        class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
      >
        <div class="overflow-x-auto">
          <table class="min-w-full text-sm">
            <thead>
              <tr
                class="text-left text-xs font-medium uppercase tracking-wide text-n-slate-10 bg-n-alpha-1 border-b border-n-weak"
              >
                <th class="py-3 px-4 min-w-[160px]">
                  {{ t('JABVOX_REPORTS.DIALER.COLS.AGENT') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.DIALER.COLS.CALLS') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.DIALER.COLS.ANSWERED') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.DIALER.COLS.DURATION') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.DIALER.COLS.NOTES') }}
                </th>
                <th class="py-3 px-4 text-right whitespace-nowrap">
                  {{ t('JABVOX_REPORTS.DIALER.TIME_CONNECTED') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="agent in agents"
                :key="agent.id"
                class="hover:bg-n-alpha-1 transition-colors"
              >
                <td class="py-3 px-4">
                  <AgentCell :agent="agent" />
                </td>
                <td class="py-3 px-4 text-right">
                  <span
                    class="inline-flex items-center gap-1 text-n-slate-12 font-semibold"
                  >
                    <span
                      class="i-lucide-phone-call size-3.5 text-n-slate-10"
                    />
                    {{ agent.total_calls || '—' }}
                  </span>
                </td>
                <td class="py-3 px-4 text-right">
                  <span
                    class="inline-flex items-center gap-1 font-semibold"
                    :class="
                      agent.answered_calls ? 'text-n-teal-11' : 'text-n-slate-9'
                    "
                  >
                    <span class="i-lucide-phone-incoming size-3.5" />
                    {{ agent.answered_calls || '—' }}
                  </span>
                </td>
                <td class="py-3 px-4 text-right font-semibold text-n-slate-12">
                  {{ formatDuration(agent.total_duration) }}
                </td>
                <td class="py-3 px-4 text-right">
                  <span
                    class="inline-flex items-center gap-1 font-semibold"
                    :class="
                      agent.notes_in_calls
                        ? 'text-n-slate-12'
                        : 'text-n-slate-9'
                    "
                  >
                    <span
                      class="i-lucide-sticky-note size-3.5 text-n-slate-10"
                    />
                    {{ agent.notes_in_calls || '—' }}
                  </span>
                </td>
                <td class="py-3 px-4 text-right">
                  <span
                    class="inline-block text-xs font-bold tabular-nums px-2 py-0.5 rounded-full"
                    :class="
                      liveConnectedSecs(agent)
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'text-n-slate-9'
                    "
                  >
                    {{
                      formatDuration(
                        liveConnectedSecs(agent),
                        !!(
                          agent.current_dialer_state_key &&
                          ACTIVE_DIALER_STATES.has(
                            agent.current_dialer_state_key
                          )
                        )
                      )
                    }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Dialer state times table -->
      <div class="flex flex-col gap-2">
        <h3
          class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
        >
          <span class="i-lucide-timer size-4 text-n-slate-10" />
          {{ t('JABVOX_REPORTS.DIALER.STATE_TIMES_TITLE') }}
        </h3>
        <div
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
        >
          <div class="overflow-x-auto">
            <table class="min-w-full text-sm">
              <thead>
                <tr
                  class="text-left text-xs font-medium uppercase tracking-wide text-n-slate-10 bg-n-alpha-1 border-b border-n-weak"
                >
                  <th class="py-3 px-4 min-w-[160px]">
                    {{ t('JABVOX_REPORTS.AGENTS.COLS.AGENT') }}
                  </th>
                  <th
                    v-for="state in dialerStates"
                    :key="state.key"
                    class="py-3 px-4 text-right whitespace-nowrap"
                  >
                    <span class="inline-flex items-center gap-1.5">
                      <span
                        class="size-2.5 rounded-full shrink-0"
                        :style="{ backgroundColor: state.color }"
                      />
                      {{ state.name }}
                    </span>
                  </th>
                  <th class="py-3 px-4 text-right whitespace-nowrap">
                    {{ t('JABVOX_REPORTS.COMMON.TOTAL') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="agent in agents"
                  :key="agent.id"
                  class="hover:bg-n-alpha-1 transition-colors"
                >
                  <td class="py-3 px-4">
                    <AgentCell :agent="agent" :size="24" compact />
                  </td>
                  <td
                    v-for="state in dialerStates"
                    :key="state.key"
                    class="py-3 px-4 text-right"
                  >
                    <span
                      class="inline-block text-xs font-semibold tabular-nums px-2 py-0.5 rounded-full"
                      :class="
                        liveSecs(agent, state.key)
                          ? 'bg-n-alpha-2 text-n-slate-12'
                          : 'text-n-slate-9'
                      "
                    >
                      {{
                        formatDuration(
                          liveSecs(agent, state.key),
                          agent.current_dialer_state_key === state.key
                        )
                      }}
                    </span>
                  </td>
                  <td class="py-3 px-4 text-right">
                    <span
                      class="inline-block text-xs font-bold tabular-nums px-2 py-0.5 rounded-full"
                      :class="
                        liveTotalSecs(agent)
                          ? 'bg-n-alpha-2 text-n-brand'
                          : 'text-n-slate-9'
                      "
                    >
                      {{
                        formatDuration(
                          liveTotalSecs(agent),
                          !!agent.current_dialer_state_key
                        )
                      }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </template>

    <!-- Empty -->
    <EmptyStateLayout
      v-else
      :title="t('JABVOX_REPORTS.COMMON.EMPTY_TITLE')"
      :subtitle="t('JABVOX_REPORTS.COMMON.EMPTY')"
    />
  </div>
</template>
