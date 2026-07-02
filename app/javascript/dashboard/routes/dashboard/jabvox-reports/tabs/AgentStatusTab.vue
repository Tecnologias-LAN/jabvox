<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import reportsAPI from 'dashboard/api/jabvox/reports';
import { emitter } from 'shared/helpers/mitt';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

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
const agentAppStateId = agent => (isOnline(agent) ? agent.app_state_id : null);
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
  if (val === 'online') return 'bg-n-teal-9';
  if (val === 'busy') return 'bg-n-amber-9';
  return 'bg-n-slate-8';
};

const dialerBadgeClass = val => {
  if (val === 'connected') return 'text-n-teal-11 bg-n-teal-3';
  if (val === 'waiting') return 'text-n-blue-11 bg-n-blue-3';
  if (val === 'in_call') return 'text-n-brand bg-n-alpha-2';
  if (val === 'in_comments') return 'text-n-amber-11 bg-n-amber-3';
  return 'text-n-slate-11 bg-n-alpha-2';
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
  <div class="flex flex-col gap-4">
    <!-- Loading -->
    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
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
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
      >
        <!-- Header: avatar + name + availability dot -->
        <div class="flex items-center gap-3 mb-4">
          <div class="relative shrink-0">
            <Avatar
              :name="agent.name || agent.email || '?'"
              :src="agent.avatar_url"
              :size="40"
              rounded-full
            />
            <span
              class="absolute bottom-0 right-0 size-3 rounded-full border-2 border-n-solid-1"
              :class="availabilityColor(agentAvailability(agent))"
            />
          </div>
          <div class="min-w-0 flex-1">
            <p class="font-semibold text-sm text-n-slate-12 truncate">
              {{ agent.name }}
            </p>
            <p class="text-xs text-n-slate-10 truncate">{{ agent.email }}</p>
          </div>
        </div>

        <!-- Divider -->
        <div class="border-t border-n-weak mb-3" />

        <!-- Rows -->
        <dl class="flex flex-col gap-2.5">
          <!-- App state -->
          <div class="flex items-center justify-between gap-2">
            <dt class="text-xs text-n-slate-10 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.APP_STATE') }}
            </dt>
            <dd class="flex items-center gap-1.5">
              <span
                v-if="agentAppStateId(agent)"
                class="size-2 rounded-full shrink-0"
                :style="{ backgroundColor: agent.app_state_color || '#94a3b8' }"
              />
              <span class="text-xs font-semibold text-n-slate-12">
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
            <dt class="text-xs text-n-slate-10 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.TIME_IN_STATE') }}
            </dt>
            <dd
              class="text-xs font-mono font-semibold tabular-nums text-n-slate-11"
            >
              {{ elapsed(agentAppStateSince(agent)) }}
            </dd>
          </div>

          <!-- Availability -->
          <div class="flex items-center justify-between gap-2">
            <dt class="text-xs text-n-slate-10 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.AVAILABILITY_LABEL') }}
            </dt>
            <dd class="text-xs font-medium text-n-slate-12">
              {{
                t(
                  `JABVOX_REPORTS.AGENT_STATUS.AVAILABILITY.${agentAvailability(agent)}`,
                  agentAvailability(agent)
                )
              }}
            </dd>
          </div>

          <!-- Divider before dialer section -->
          <div class="border-t border-n-weak pt-1" />

          <!-- Dialer state badge -->
          <div class="flex items-center justify-between gap-2">
            <dt class="text-xs text-n-slate-10 shrink-0">
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
            <dt class="text-xs text-n-slate-10 shrink-0">
              {{ t('JABVOX_REPORTS.AGENT_STATUS.TIME_IN_DIALER') }}
            </dt>
            <dd
              class="text-xs font-mono font-semibold tabular-nums text-n-brand"
            >
              {{ elapsed(agent.dialer_state_since) }}
            </dd>
          </div>
        </dl>
      </div>
    </div>

    <!-- Empty -->
    <EmptyStateLayout
      v-else
      :title="t('JABVOX_REPORTS.COMMON.EMPTY_TITLE')"
      :subtitle="t('JABVOX_REPORTS.COMMON.EMPTY')"
    />

    <!-- Footer note -->
    <p
      class="text-xs text-n-slate-10 text-center flex items-center justify-center gap-1.5"
    >
      <span class="i-lucide-radio size-3" />
      {{ t('JABVOX_REPORTS.AGENT_STATUS.LIVE_NOTE') }}
    </p>
  </div>
</template>
