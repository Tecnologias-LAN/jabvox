<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import reportsAPI from 'dashboard/api/jabvox/reports';

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

const byStatusList = computed(() =>
  Object.entries(byStatus.value).map(([k, v]) => ({ key: k, count: v }))
);

const hasAgents = computed(() => agents.value.length > 0);

const elapsedSecs = computed(() =>
  fetchedAt.value ? Math.floor((now.value - fetchedAt.value) / 1000) : 0
);

const ACTIVE_DIALER_STATES = new Set(['connected', 'waiting', 'in_call', 'in_comments']);

const liveSecs = (agent, stateKey) => {
  const base = agent.state_times?.[stateKey] || 0;
  return agent.current_dialer_state_key === stateKey ? base + elapsedSecs.value : base;
};

const liveConnectedSecs = agent => {
  const base = Object.entries(agent.state_times || {})
    .filter(([k]) => ACTIVE_DIALER_STATES.has(k))
    .reduce((s, [, v]) => s + (v || 0), 0);
  const isActive = agent.current_dialer_state_key && ACTIVE_DIALER_STATES.has(agent.current_dialer_state_key);
  return base + (isActive ? elapsedSecs.value : 0);
};

const liveTotalSecs = agent => {
  const base = Object.values(agent.state_times || {}).reduce((s, v) => s + (v || 0), 0);
  return base + (agent.current_dialer_state_key ? elapsedSecs.value : 0);
};

const formatDuration = (seconds, live = false) => {
  if (!seconds && !live) return '—';
  const s = seconds || 0;
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (live) {
    if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m ${String(sec).padStart(2, '0')}s`;
    if (m > 0) return `${m}m ${String(sec).padStart(2, '0')}s`;
    return `${sec}s`;
  }
  if (h > 0) return `${h}h ${m}m`;
  return m > 0 ? `${m}m` : '< 1m';
};

onMounted(() => {
  fetch();
  ticker = setInterval(() => { now.value = Date.now(); }, 1000);
});
onUnmounted(() => clearInterval(ticker));
</script>

<template>
  <div class="space-y-5">
    <!-- Filters -->
    <div
      class="flex flex-wrap gap-3 p-4 bg-slate-50 dark:bg-slate-800/60 rounded-xl border border-slate-200 dark:border-slate-700"
    >
      <div class="flex flex-col gap-1">
        <label class="text-xs font-medium text-slate-600 dark:text-slate-400">{{
          t('JABVOX_REPORTS.COMMON.FILTER_FROM')
        }}</label>
        <input
          v-model="filters.date_from"
          type="date"
          class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs font-medium text-slate-600 dark:text-slate-400">{{
          t('JABVOX_REPORTS.COMMON.FILTER_TO')
        }}</label>
        <input
          v-model="filters.date_to"
          type="date"
          class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
        />
      </div>
      <div class="flex items-end">
        <button
          :disabled="loading"
          class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium disabled:opacity-50 transition-colors"
          @click="fetch"
        >
          <span class="i-lucide-search w-4 h-4" />
          {{ t('JABVOX_REPORTS.COMMON.APPLY') }}
        </button>
      </div>
    </div>

    <!-- Summary cards -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-1 shadow-sm"
      >
        <p class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          {{ t('JABVOX_REPORTS.DIALER.STATS.TOTAL_CALLS') }}
        </p>
        <p class="text-2xl font-bold text-slate-900 dark:text-slate-50">
          {{ totals.total_calls }}
        </p>
      </div>
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-1 shadow-sm"
      >
        <p class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          {{ t('JABVOX_REPORTS.DIALER.STATS.TOTAL_ANSWERED') }}
        </p>
        <p class="text-2xl font-bold text-green-600 dark:text-green-400">
          {{ totals.total_answered }}
        </p>
      </div>
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-1 shadow-sm"
      >
        <p class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          {{ t('JABVOX_REPORTS.DIALER.STATS.TOTAL_DURATION') }}
        </p>
        <p class="text-xl font-bold text-woot-600 dark:text-woot-400">
          {{ formatDuration(totals.total_duration) }}
        </p>
      </div>
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-1 shadow-sm"
      >
        <p class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          {{ t('JABVOX_REPORTS.DIALER.STATS.BY_STATUS') }}
        </p>
        <div class="flex flex-wrap gap-1 pt-0.5">
          <span
            v-for="s in byStatusList"
            :key="s.key"
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-200"
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
      class="text-sm text-slate-400 animate-pulse text-center py-16"
    >
      {{ t('JABVOX_REPORTS.COMMON.LOADING') }}
    </div>

    <template v-else-if="hasAgents">
      <!-- Activity table -->
      <div
        class="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800/50 shadow-sm"
      >
        <table
          class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
        >
          <thead class="bg-slate-50 dark:bg-slate-800/80">
            <tr
              class="text-left text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wide"
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
          <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
            <tr
              v-for="agent in agents"
              :key="agent.id"
              class="hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors"
            >
              <td class="py-3 px-4">
                <div class="flex items-center gap-2.5">
                  <img
                    v-if="agent.avatar_url"
                    :src="agent.avatar_url"
                    :alt="agent.name"
                    class="w-7 h-7 rounded-full object-cover shrink-0"
                  />
                  <span
                    v-else
                    class="w-7 h-7 rounded-full bg-woot-100 dark:bg-woot-900/30 flex items-center justify-center shrink-0"
                  >
                    <span class="text-xs font-semibold text-woot-600">{{
                      agent.name?.charAt(0)
                    }}</span>
                  </span>
                  <div>
                    <p class="font-medium text-slate-900 dark:text-slate-50 leading-tight">
                      {{ agent.name }}
                    </p>
                    <p class="text-xs text-slate-400">{{ agent.email }}</p>
                  </div>
                </div>
              </td>
              <td class="py-3 px-4 text-right">
                <span class="inline-flex items-center gap-1 text-slate-700 dark:text-slate-300 font-semibold">
                  <span class="i-lucide-phone-call w-3.5 h-3.5 text-slate-400" />
                  {{ agent.total_calls || '—' }}
                </span>
              </td>
              <td class="py-3 px-4 text-right">
                <span
                  class="inline-flex items-center gap-1 font-semibold"
                  :class="agent.answered_calls ? 'text-green-600 dark:text-green-400' : 'text-slate-300 dark:text-slate-600'"
                >
                  <span class="i-lucide-phone-incoming w-3.5 h-3.5" />
                  {{ agent.answered_calls || '—' }}
                </span>
              </td>
              <td class="py-3 px-4 text-right font-semibold text-slate-700 dark:text-slate-300">
                {{ formatDuration(agent.total_duration) }}
              </td>
              <td class="py-3 px-4 text-right">
                <span
                  class="inline-flex items-center gap-1 font-semibold"
                  :class="agent.notes_in_calls ? 'text-slate-700 dark:text-slate-300' : 'text-slate-300 dark:text-slate-600'"
                >
                  <span class="i-lucide-sticky-note w-3.5 h-3.5 text-slate-400" />
                  {{ agent.notes_in_calls || '—' }}
                </span>
              </td>
              <td class="py-3 px-4 text-right">
                <span
                  class="inline-block text-xs font-bold tabular-nums px-2 py-0.5 rounded-full"
                  :class="
                    liveConnectedSecs(agent)
                      ? 'bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-300'
                      : 'text-slate-300 dark:text-slate-600'
                  "
                >
                  {{ formatDuration(liveConnectedSecs(agent), !!(agent.current_dialer_state_key && ACTIVE_DIALER_STATES.has(agent.current_dialer_state_key))) }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Dialer state times table -->
      <div class="space-y-2">
        <h3
          class="text-sm font-semibold text-slate-700 dark:text-slate-300 flex items-center gap-2"
        >
          <span class="i-lucide-timer w-4 h-4 text-slate-400" />
          {{ t('JABVOX_REPORTS.DIALER.STATE_TIMES_TITLE') }}
        </h3>
        <div
          class="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800/50 shadow-sm"
        >
          <table
            class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
          >
            <thead class="bg-slate-50 dark:bg-slate-800/80">
              <tr
                class="text-left text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wide"
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
                      class="w-2.5 h-2.5 rounded-full shrink-0"
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
            <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
              <tr
                v-for="agent in agents"
                :key="agent.id"
                class="hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors"
              >
                <td class="py-3 px-4">
                  <div class="flex items-center gap-2.5">
                    <img
                      v-if="agent.avatar_url"
                      :src="agent.avatar_url"
                      :alt="agent.name"
                      class="w-6 h-6 rounded-full object-cover shrink-0"
                    />
                    <span
                      v-else
                      class="w-6 h-6 rounded-full bg-woot-100 dark:bg-woot-900/30 flex items-center justify-center shrink-0"
                    >
                      <span class="text-[10px] font-semibold text-woot-600">{{
                        agent.name?.charAt(0)
                      }}</span>
                    </span>
                    <span class="font-medium text-slate-800 dark:text-slate-100 text-xs truncate max-w-[120px]">
                      {{ agent.name }}
                    </span>
                  </div>
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
                        ? 'bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-200'
                        : 'text-slate-300 dark:text-slate-600'
                    "
                  >
                    {{ formatDuration(liveSecs(agent, state.key), agent.current_dialer_state_key === state.key) }}
                  </span>
                </td>
                <td class="py-3 px-4 text-right">
                  <span
                    class="inline-block text-xs font-bold tabular-nums px-2 py-0.5 rounded-full"
                    :class="
                      liveTotalSecs(agent)
                        ? 'bg-woot-50 dark:bg-woot-900/20 text-woot-700 dark:text-woot-300'
                        : 'text-slate-300 dark:text-slate-600'
                    "
                  >
                    {{ formatDuration(liveTotalSecs(agent), !!agent.current_dialer_state_key) }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>

    <!-- Empty -->
    <div v-else class="text-sm text-slate-400 text-center py-16">
      {{ t('JABVOX_REPORTS.COMMON.EMPTY') }}
    </div>
  </div>
</template>
