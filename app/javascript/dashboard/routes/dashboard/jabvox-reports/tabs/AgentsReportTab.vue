<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import reportsAPI from 'dashboard/api/jabvox/reports';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import FilterBar from '../components/FilterBar.vue';
import AgentCell from '../components/AgentCell.vue';

const { t } = useI18n();
const router = useRouter();

const loading = ref(false);
const agents = ref([]);
const appStates = ref([]);
const fetchedAt = ref(null);
const now = ref(Date.now());
let ticker = null;

const filters = ref({ date_from: '', date_to: '' });

// Clicking an agent's metric cell opens that metric's drill-down filtered to
// THAT agent, carrying the same date range this report uses. The drill-down
// route reads from/to as a custom range (preset=custom).
const openDrilldown = (agent, metricKey) => {
  // Las filas de Hermes (bot) no tienen user_id numérico: su detalle vive en el
  // reporte "Actividad de Hermes", no en el drill-down por agente.
  if (agent.is_hermes) return;
  const query = {
    preset: 'custom',
    agent_ids: String(agent.id),
    agent_name: agent.name,
    back: 'agents',
  };
  if (filters.value.date_from) query.from = filters.value.date_from;
  if (filters.value.date_to) query.to = filters.value.date_to;
  router.push({
    name: 'jabvox_reports_drilldown',
    params: { metricKey },
    query,
  });
};

const fetch = async () => {
  loading.value = true;
  try {
    const { data } = await reportsAPI.getAgents(filters.value);
    agents.value = data.agents || [];
    appStates.value = data.app_states || [];
    fetchedAt.value = Date.now();
    now.value = Date.now();
  } catch {
    agents.value = [];
    appStates.value = [];
    fetchedAt.value = null;
  } finally {
    loading.value = false;
  }
};

const resetFilters = () => {
  filters.value = { date_from: '', date_to: '' };
  fetch();
};

const visibleStates = computed(() => appStates.value);
const hasStateTimes = computed(() => visibleStates.value.length > 0);

const elapsedSecs = computed(() =>
  fetchedAt.value ? Math.floor((now.value - fetchedAt.value) / 1000) : 0
);

const liveSeconds = (agent, stateKey) => {
  const base = agent.state_times?.[stateKey] || 0;
  return agent.current_state_key === stateKey ? base + elapsedSecs.value : base;
};

const liveTotalSeconds = agent => {
  const base = Object.values(agent.state_times || {}).reduce(
    (s, v) => s + (v || 0),
    0
  );
  return agent.current_state_key ? base + elapsedSecs.value : base;
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

    <!-- Loading -->
    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
      {{ t('JABVOX_REPORTS.COMMON.LOADING') }}
    </div>

    <template v-else-if="agents.length">
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
                <th class="py-3 px-4">
                  {{ t('JABVOX_REPORTS.AGENTS.COLS.AGENT') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.AGENTS.COLS.RESOLVED') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.AGENTS.COLS.CONVERSATIONS') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.AGENTS.COLS.MESSAGES') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.AGENTS.COLS.NOTES') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.AGENTS.COLS.MANAGEMENTS') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.AGENTS.COLS.ORDERS') }}
                </th>
                <th class="py-3 px-4 text-right">
                  {{ t('JABVOX_REPORTS.AGENTS.COLS.CALLS') }}
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
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 font-semibold rounded-md px-1.5 py-0.5 transition-colors hover:bg-n-brand/10 hover:text-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :class="
                      agent.resolved_count
                        ? 'text-n-slate-12'
                        : 'text-n-slate-9 pointer-events-none'
                    "
                    :title="t('JABVOX_REPORTS.AGENTS.DRILLDOWN_HINT')"
                    @click="openDrilldown(agent, 'resolved')"
                  >
                    <span
                      class="i-lucide-circle-check-big size-3.5 text-n-slate-10"
                    />
                    {{ agent.resolved_count }}
                  </button>
                </td>
                <td class="py-3 px-4 text-right">
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 font-semibold rounded-md px-1.5 py-0.5 transition-colors hover:bg-n-brand/10 hover:text-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :class="
                      agent.conversations_count
                        ? 'text-n-slate-12'
                        : 'text-n-slate-9 pointer-events-none'
                    "
                    :title="t('JABVOX_REPORTS.AGENTS.DRILLDOWN_HINT')"
                    @click="openDrilldown(agent, 'conversations')"
                  >
                    <span
                      class="i-lucide-messages-square size-3.5 text-n-slate-10"
                    />
                    {{ agent.conversations_count }}
                  </button>
                </td>
                <td class="py-3 px-4 text-right">
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 font-semibold rounded-md px-1.5 py-0.5 transition-colors hover:bg-n-brand/10 hover:text-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :class="
                      agent.messages_sent
                        ? 'text-n-slate-12'
                        : 'text-n-slate-9 pointer-events-none'
                    "
                    :title="t('JABVOX_REPORTS.AGENTS.DRILLDOWN_HINT')"
                    @click="openDrilldown(agent, 'messages_sent')"
                  >
                    <span
                      class="i-lucide-message-square size-3.5 text-n-slate-10"
                    />
                    {{ agent.messages_sent }}
                  </button>
                </td>
                <td class="py-3 px-4 text-right">
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 font-semibold rounded-md px-1.5 py-0.5 transition-colors hover:bg-n-brand/10 hover:text-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :class="
                      agent.notes_added
                        ? 'text-n-slate-12'
                        : 'text-n-slate-9 pointer-events-none'
                    "
                    :title="t('JABVOX_REPORTS.AGENTS.DRILLDOWN_HINT')"
                    @click="openDrilldown(agent, 'private_notes')"
                  >
                    <span
                      class="i-lucide-sticky-note size-3.5 text-n-slate-10"
                    />
                    {{ agent.notes_added }}
                  </button>
                </td>
                <td class="py-3 px-4 text-right">
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 font-semibold rounded-md px-1.5 py-0.5 transition-colors hover:bg-n-brand/10 hover:text-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :class="
                      agent.managements_added
                        ? 'text-n-slate-12'
                        : 'text-n-slate-9 pointer-events-none'
                    "
                    :title="t('JABVOX_REPORTS.AGENTS.DRILLDOWN_HINT')"
                    @click="openDrilldown(agent, 'managements')"
                  >
                    <span
                      class="i-lucide-clipboard-list size-3.5 text-n-slate-10"
                    />
                    {{ agent.managements_added }}
                  </button>
                </td>
                <td class="py-3 px-4 text-right">
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 font-semibold rounded-md px-1.5 py-0.5 transition-colors hover:bg-n-brand/10 hover:text-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :class="
                      agent.orders_placed
                        ? 'text-n-slate-12'
                        : 'text-n-slate-9 pointer-events-none'
                    "
                    :title="t('JABVOX_REPORTS.AGENTS.DRILLDOWN_HINT')"
                    @click="openDrilldown(agent, 'orders')"
                  >
                    <span class="i-lucide-package size-3.5 text-n-slate-10" />
                    {{ agent.orders_placed }}
                  </button>
                </td>
                <td class="py-3 px-4 text-right">
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 font-semibold rounded-md px-1.5 py-0.5 transition-colors hover:bg-n-brand/10 hover:text-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :class="
                      agent.calls_made
                        ? 'text-n-slate-12'
                        : 'text-n-slate-9 pointer-events-none'
                    "
                    :title="t('JABVOX_REPORTS.AGENTS.DRILLDOWN_HINT')"
                    @click="openDrilldown(agent, 'calls')"
                  >
                    <span class="i-lucide-phone size-3.5 text-n-slate-10" />
                    {{ agent.calls_made }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- State times table -->
      <div class="flex flex-col gap-2">
        <h3
          class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
        >
          <span class="i-lucide-clock size-4 text-n-slate-10" />
          {{ t('JABVOX_REPORTS.AGENTS.STATE_TIMES_TITLE') }}
        </h3>

        <div
          v-if="hasStateTimes"
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
                    v-for="state in visibleStates"
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
                    v-for="state in visibleStates"
                    :key="state.key"
                    class="py-3 px-4 text-right"
                  >
                    <span
                      class="inline-block text-xs font-semibold tabular-nums px-2 py-0.5 rounded-full"
                      :class="
                        liveSeconds(agent, state.key)
                          ? 'bg-n-alpha-2 text-n-slate-12'
                          : 'text-n-slate-9'
                      "
                    >
                      {{
                        formatDuration(
                          liveSeconds(agent, state.key),
                          agent.current_state_key === state.key
                        )
                      }}
                    </span>
                  </td>
                  <td class="py-3 px-4 text-right">
                    <span
                      class="inline-block text-xs font-bold tabular-nums px-2 py-0.5 rounded-full"
                      :class="
                        liveTotalSeconds(agent)
                          ? 'bg-n-alpha-2 text-n-brand'
                          : 'text-n-slate-9'
                      "
                    >
                      {{
                        formatDuration(
                          liveTotalSeconds(agent),
                          !!agent.current_state_key
                        )
                      }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <p
          v-else
          class="text-xs text-n-slate-11 text-center py-6 rounded-2xl border border-n-weak bg-n-solid-1"
        >
          {{ t('JABVOX_REPORTS.AGENTS.STATE_TIMES_EMPTY') }}
        </p>
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
