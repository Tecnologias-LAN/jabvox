<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import reportsAPI from 'dashboard/api/jabvox/reports';

const { t } = useI18n();

const loading = ref(false);
const agents = ref([]);
const appStates = ref([]);
const fetchedAt = ref(null);
const now = ref(Date.now());
let ticker = null;

const filters = ref({ date_from: '', date_to: '' });

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

    <!-- Loading -->
    <div
      v-if="loading"
      class="text-sm text-slate-400 animate-pulse text-center py-16"
    >
      {{ t('JABVOX_REPORTS.COMMON.LOADING') }}
    </div>

    <template v-else-if="agents.length">
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
              <th class="py-3 px-4">
                {{ t('JABVOX_REPORTS.AGENTS.COLS.AGENT') }}
              </th>
              <th class="py-3 px-4 text-right">
                {{ t('JABVOX_REPORTS.AGENTS.COLS.MESSAGES') }}
              </th>
              <th class="py-3 px-4 text-right">
                {{ t('JABVOX_REPORTS.AGENTS.COLS.NOTES') }}
              </th>
              <th class="py-3 px-4 text-right">
                {{ t('JABVOX_REPORTS.AGENTS.COLS.ORDERS') }}
              </th>
              <th class="py-3 px-4 text-right">
                {{ t('JABVOX_REPORTS.AGENTS.COLS.CALLS') }}
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
                    <p
                      class="font-medium text-slate-900 dark:text-slate-50 leading-tight"
                    >
                      {{ agent.name }}
                    </p>
                    <p class="text-xs text-slate-400">{{ agent.email }}</p>
                  </div>
                </div>
              </td>
              <td class="py-3 px-4 text-right">
                <span
                  class="inline-flex items-center gap-1 text-slate-700 dark:text-slate-300 font-semibold"
                >
                  <span
                    class="i-lucide-message-square w-3.5 h-3.5 text-slate-400"
                  />
                  {{ agent.messages_sent }}
                </span>
              </td>
              <td class="py-3 px-4 text-right">
                <span
                  class="inline-flex items-center gap-1 text-slate-700 dark:text-slate-300 font-semibold"
                >
                  <span
                    class="i-lucide-sticky-note w-3.5 h-3.5 text-slate-400"
                  />
                  {{ agent.notes_added }}
                </span>
              </td>
              <td class="py-3 px-4 text-right">
                <span
                  class="inline-flex items-center gap-1 text-slate-700 dark:text-slate-300 font-semibold"
                >
                  <span class="i-lucide-package w-3.5 h-3.5 text-slate-400" />
                  {{ agent.orders_placed }}
                </span>
              </td>
              <td class="py-3 px-4 text-right">
                <span
                  class="inline-flex items-center gap-1 text-slate-700 dark:text-slate-300 font-semibold"
                >
                  <span class="i-lucide-phone w-3.5 h-3.5 text-slate-400" />
                  {{ agent.calls_made }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- State times table -->
      <div class="space-y-2">
        <h3
          class="text-sm font-semibold text-slate-700 dark:text-slate-300 flex items-center gap-2"
        >
          <span class="i-lucide-clock w-4 h-4 text-slate-400" />
          {{ t('JABVOX_REPORTS.AGENTS.STATE_TIMES_TITLE') }}
        </h3>

        <div
          v-if="hasStateTimes"
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
                  v-for="state in visibleStates"
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
                    <span
                      class="font-medium text-slate-800 dark:text-slate-100 text-xs truncate max-w-[120px]"
                      >{{ agent.name }}</span
                    >
                  </div>
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
                        ? 'bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-200'
                        : 'text-slate-300 dark:text-slate-600'
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
                        ? 'bg-woot-50 dark:bg-woot-900/20 text-woot-700 dark:text-woot-300'
                        : 'text-slate-300 dark:text-slate-600'
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

        <p
          v-else
          class="text-xs text-slate-400 text-center py-6 bg-white dark:bg-slate-800/50 rounded-xl border border-slate-200 dark:border-slate-700"
        >
          {{ t('JABVOX_REPORTS.AGENTS.STATE_TIMES_EMPTY') }}
        </p>
      </div>
    </template>

    <!-- Empty -->
    <div v-else class="text-sm text-slate-400 text-center py-16">
      {{ t('JABVOX_REPORTS.COMMON.EMPTY') }}
    </div>
  </div>
</template>
