<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import reportsAPI from 'dashboard/api/jabvox/reports';
import { emitter } from 'shared/helpers/mitt';

const { t } = useI18n();

const loading = ref(false);
const agents = ref([]);
const now = ref(Date.now());
let pollInterval = null;
let tickInterval = null;

const agentAvailability = agent => agent.availability;

const fetch = async () => {
  if (loading.value) return;
  loading.value = agents.value.length === 0;
  try {
    const { data } = await reportsAPI.getAgentStatus();
    agents.value = data.agents || [];
  } finally {
    loading.value = false;
  }
};

const isOnline = agent => agentAvailability(agent) !== 'offline';
const agentAppStateName = agent =>
  isOnline(agent) ? agent.app_state_name : null;
const agentAppStateId = agent =>
  isOnline(agent) ? agent.app_state_id : null;
const agentAppStateSince = agent =>
  isOnline(agent) ? agent.app_state_since : null;

const elapsed = sinceIso => {
  if (!sinceIso) return null;
  const secs = Math.max(
    0,
    Math.floor((now.value - new Date(sinceIso).getTime()) / 1000)
  );
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h) return `${h}h ${m}m ${s}s`;
  if (m) return `${m}m ${s}s`;
  return `${s}s`;
};

const availabilityColor = val => {
  if (val === 'online') return 'bg-green-500';
  if (val === 'busy') return 'bg-amber-500';
  return 'bg-slate-400';
};

const dialerBadgeClass = val => {
  if (val === 'connected')
    return 'text-green-700 dark:text-green-300 bg-green-100 dark:bg-green-900/30';
  if (val === 'waiting')
    return 'text-blue-700 dark:text-blue-300 bg-blue-100 dark:bg-blue-900/30';
  if (val === 'in_call')
    return 'text-woot-700 dark:text-woot-300 bg-woot-100 dark:bg-woot-900/30';
  if (val === 'in_comments')
    return 'text-amber-700 dark:text-amber-300 bg-amber-100 dark:bg-amber-900/30';
  return 'text-slate-500 dark:text-slate-400 bg-slate-100 dark:bg-slate-700';
};

const dialerIsActive = val => val && val !== 'inactive';

const onVisibilityChange = () => {
  if (!document.hidden) fetch();
};

onMounted(() => {
  fetch();
  pollInterval = setInterval(fetch, 30000);
  tickInterval = setInterval(() => {
    now.value = Date.now();
  }, 1000);
  document.addEventListener('visibilitychange', onVisibilityChange);
  emitter.on('jabvox.agent_state_changed', fetch);
});

onUnmounted(() => {
  clearInterval(pollInterval);
  clearInterval(tickInterval);
  document.removeEventListener('visibilitychange', onVisibilityChange);
  emitter.off('jabvox.agent_state_changed', fetch);
});
</script>

<template>
  <div class="space-y-4">
    <!-- Loading -->
    <div
      v-if="loading"
      class="text-sm text-slate-400 animate-pulse text-center py-16"
    >
      {{ t('JABVOX_REPORTS.COMMON.LOADING') }}
    </div>

    <!-- Agent cards grid -->
    <div
      v-else-if="agents.length"
      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4"
    >
      <div
        v-for="agent in agents"
        :key="agent.id"
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 shadow-sm"
      >
        <!-- Header: avatar + name + availability dot -->
        <div class="flex items-center gap-3 mb-4">
          <div class="relative shrink-0">
            <img
              v-if="agent.avatar_url"
              :src="agent.avatar_url"
              :alt="agent.name"
              class="w-10 h-10 rounded-full object-cover"
            />
            <span
              v-else
              class="w-10 h-10 rounded-full bg-woot-100 dark:bg-woot-900/30 flex items-center justify-center"
            >
              <span class="text-sm font-bold text-woot-600">{{
                agent.name?.charAt(0)?.toUpperCase()
              }}</span>
            </span>
            <span
              class="absolute bottom-0 right-0 w-3 h-3 rounded-full border-2 border-white dark:border-slate-800"
              :class="availabilityColor(agentAvailability(agent))"
            />
          </div>
          <div class="min-w-0 flex-1">
            <p
              class="font-semibold text-sm text-slate-900 dark:text-slate-50 truncate"
            >
              {{ agent.name }}
            </p>
            <p class="text-xs text-slate-400 truncate">{{ agent.email }}</p>
          </div>
        </div>

        <!-- Divider -->
        <div class="border-t border-slate-100 dark:border-slate-700 mb-3" />

        <!-- Rows -->
        <dl class="space-y-2.5">
          <!-- App state -->
          <div class="flex items-center justify-between gap-2">
            <dt class="text-xs text-slate-500 dark:text-slate-400 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.APP_STATE') }}
            </dt>
            <dd class="flex items-center gap-1.5">
              <span
                v-if="agentAppStateId(agent)"
                class="w-2 h-2 rounded-full shrink-0"
                :style="{ backgroundColor: agent.app_state_color || '#94a3b8' }"
              />
              <span
                class="text-xs font-semibold text-slate-700 dark:text-slate-300"
              >
                {{
                  isOnline(agent)
                    ? agentAppStateName(agent) ||
                      t('JABVOX_REPORTS.AGENT_STATUS.ACTIVE')
                    : '—'
                }}
              </span>
            </dd>
          </div>

          <!-- Time in app state (live ticker) -->
          <div
            v-if="agentAppStateSince(agent)"
            class="flex items-center justify-between gap-2"
          >
            <dt class="text-xs text-slate-500 dark:text-slate-400 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.TIME_IN_STATE') }}
            </dt>
            <dd
              class="text-xs font-mono font-semibold tabular-nums text-slate-600 dark:text-slate-300"
            >
              {{ elapsed(agentAppStateSince(agent)) }}
            </dd>
          </div>

          <!-- Availability -->
          <div class="flex items-center justify-between gap-2">
            <dt class="text-xs text-slate-500 dark:text-slate-400 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.AVAILABILITY_LABEL') }}
            </dt>
            <dd class="text-xs font-medium text-slate-700 dark:text-slate-300">
              {{
                t(
                  `JABVOX_REPORTS.AGENT_STATUS.AVAILABILITY.${agentAvailability(agent)}`,
                  agentAvailability(agent)
                )
              }}
            </dd>
          </div>

          <!-- Divider before dialer section -->
          <div class="border-t border-slate-100 dark:border-slate-700 pt-1" />

          <!-- Dialer state badge -->
          <div class="flex items-center justify-between gap-2">
            <dt class="text-xs text-slate-500 dark:text-slate-400 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.DIALER_STATE') }}
            </dt>
            <dd>
              <span
                class="text-xs px-2 py-0.5 rounded-full font-semibold"
                :class="dialerBadgeClass(agent.dialer_state)"
              >
                {{
                  t(
                    `JABVOX_REPORTS.AGENT_STATUS.DIALER.${agent.dialer_state}`,
                    agent.dialer_state
                  )
                }}
              </span>
            </dd>
          </div>

          <!-- Time in dialer state (live ticker) — only when active -->
          <div
            v-if="
              dialerIsActive(agent.dialer_state) && agent.dialer_state_since
            "
            class="flex items-center justify-between gap-2"
          >
            <dt class="text-xs text-slate-500 dark:text-slate-400 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.TIME_IN_DIALER') }}
            </dt>
            <dd
              class="text-xs font-mono font-semibold tabular-nums text-woot-600 dark:text-woot-400"
            >
              {{ elapsed(agent.dialer_state_since) }}
            </dd>
          </div>
        </dl>
      </div>
    </div>

    <!-- Empty -->
    <div v-else class="text-sm text-slate-400 text-center py-16">
      {{ t('JABVOX_REPORTS.COMMON.EMPTY') }}
    </div>

    <!-- Footer note -->
    <p
      class="text-xs text-slate-400 text-center flex items-center justify-center gap-1.5"
    >
      <span class="i-lucide-radio w-3 h-3" />
      {{ t('JABVOX_REPORTS.AGENT_STATUS.LIVE_NOTE') }}
    </p>
  </div>
</template>
