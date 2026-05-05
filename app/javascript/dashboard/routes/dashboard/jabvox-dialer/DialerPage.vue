<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { dialerAccessesAPI } from 'dashboard/api/jabvox/dialer';
import messageAPI from 'dashboard/api/inbox/message';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const campaigns = useMapGetter('jabvoxDialer/getCampaigns');
const dialerStates = useMapGetter('jabvoxDialer/getDialerStates');
const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');
const uiFlags = useMapGetter('jabvoxDialer/getUIFlags');
const currentUserId = useMapGetter('getCurrentUserID');

const SESSION_KEY = 'jabvox_dialer_session';

const canAccess = ref(true);
const checkingAccess = ref(true);
const connected = ref(false);
const activeCampaign = ref(null);
const connecting = ref(false);
const activeDialerState = ref(null); // null = available
const stateDropdownOpen = ref(false);
const activeCall = ref(null);
const dialingCall = ref(null); // call initiated, waiting for agent connection
const lastCall = ref(null); // persists call info during wrapup for gestión note
const dialerStatusMessage = ref(null);
const wrapupRemaining = ref(0);
const inWrapup = ref(false);
const wrapupNote = ref('');
const wrapupStateId = ref(null);
const isSavingNote = ref(false);
let heartbeatTimer = null;
let requestCallTimer = null;
let wrapupTimer = null;
const myCampaigns = computed(() => {
  const myId = Number(currentUserId.value);
  if (!myId) return [];
  return (campaigns.value || []).filter(
    c =>
      c.status_jabvox === 'active' &&
      Array.isArray(c.agent_ids_jabvox) &&
      c.agent_ids_jabvox.some(id => Number(id) === myId)
  );
});

const isAvailable = computed(
  () =>
    connected.value &&
    activeDialerState.value === null &&
    !inWrapup.value &&
    !dialingCall.value &&
    !activeCall.value
);

const statusColor = computed(() => {
  if (!connected.value) return '#94a3b8';
  if (!activeDialerState.value) return '#22c55e';
  return activeDialerState.value.color || '#f59e0b';
});

const statusLabel = computed(() => {
  if (!connected.value) return t('JABVOX_DIALER.DISCONNECTED');
  if (!activeDialerState.value) return t('JABVOX_DIALER.CONNECTED_STATUS');
  return activeDialerState.value.name;
});

const onCallAssigned = data => {
  const pendingId = dialingCall.value?.dialer_contact_id;
  dialingCall.value = null;
  activeCall.value = { ...data, dialer_contact_id: data.dialer_contact_id || pendingId };
  inWrapup.value = false;
  clearWrapupTimer();
};

const clearWrapupTimer = () => {
  if (wrapupTimer) {
    clearInterval(wrapupTimer);
    wrapupTimer = null;
  }
};

const endWrapup = () => {
  clearWrapupTimer();
  inWrapup.value = false;
  wrapupRemaining.value = 0;
  lastCall.value = null;
  wrapupNote.value = '';
  wrapupStateId.value = null;
  if (connected.value && activeDialerState.value === null) {
    // Unpause agent in Asterisk queue before requesting next call
    dialerAccessesAPI.updateState(null).catch(() => {});
    startRequestCallPolling();
  }
};

const saveWrapupNote = async () => {
  const convId = lastCall.value?.conversation_id;
  const stateObj = managementStates.value.find(s => s.id === wrapupStateId.value);
  const note = wrapupNote.value.trim() || stateObj?.name_jabvox || '';
  if (!convId || !note || isSavingNote.value) return;
  const payload = {
    conversationId: convId,
    message: note,
    private: true,
    echo_id: `jabvox_dialer_${Date.now()}`,
  };
  if (stateObj) {
    payload.contentAttributes = {
      jabvox_management_state_id: stateObj.id,
      jabvox_management_state_name: stateObj.name_jabvox || '',
      jabvox_management_state_color: stateObj.color_jabvox || '',
    };
  }
  isSavingNote.value = true;
  try {
    await messageAPI.create(payload);
  } catch {
    // best-effort
  } finally {
    isSavingNote.value = false;
  }
};

const startWrapup = () => {
  stopRequestCallPolling();
  lastCall.value = activeCall.value || dialingCall.value || lastCall.value;
  inWrapup.value = true;
  const seconds = activeCampaign.value?.wrapup_time_jabvox || 30;
  wrapupRemaining.value = seconds;
  clearWrapupTimer();
  wrapupTimer = setInterval(() => {
    wrapupRemaining.value -= 1;
    if (wrapupRemaining.value <= 0) saveWrapupNote().then(endWrapup);
  }, 1000);
};

const openConversation = () => {
  const convId = activeCall.value?.conversation_id;
  if (!convId) return;
  router.push({ name: 'inbox_conversation', params: { conversation_id: convId } });
};

const onEndCall = () => {
  const dialerContactId = activeCall.value?.dialer_contact_id || dialingCall.value?.dialer_contact_id;
  lastCall.value = activeCall.value || dialingCall.value || lastCall.value;
  activeCall.value = null;
  dialingCall.value = null;
  if (dialerContactId) dialerAccessesAPI.endCall(dialerContactId).catch(() => {});
  startWrapup();
};

const onCallEnded = () => {
  if (!activeCall.value && !dialingCall.value) return;
  const dialerContactId = activeCall.value?.dialer_contact_id || dialingCall.value?.dialer_contact_id;
  lastCall.value = activeCall.value || dialingCall.value || lastCall.value;
  activeCall.value = null;
  dialingCall.value = null;
  if (dialerContactId) dialerAccessesAPI.endCall(dialerContactId).catch(() => {});
  startWrapup();
};

const stopHeartbeat = () => {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }
};

const startHeartbeat = () => {
  stopHeartbeat();
  heartbeatTimer = setInterval(
    () => {
      dialerAccessesAPI.heartbeat().catch(() => {});
    },
    4 * 60 * 1000
  );
};

const stopRequestCallPolling = () => {
  if (requestCallTimer) {
    clearInterval(requestCallTimer);
    requestCallTimer = null;
  }
};

const doRequestCall = async () => {
  if (!connected.value || activeDialerState.value !== null || activeCall.value || dialingCall.value || inWrapup.value)
    return;
  try {
    const { data } = await dialerAccessesAPI.requestCall();
    if (data.success) {
      dialingCall.value = { dialer_contact_id: data.dialer_contact_id };
      stopRequestCallPolling();
      dialerStatusMessage.value = null;
    } else if (data.queued === false) {
      dialerStatusMessage.value = data.message || null;
    }
  } catch {
    // ignore - retry next tick
  }
};

const startRequestCallPolling = () => {
  stopRequestCallPolling();
  doRequestCall();
  requestCallTimer = setInterval(doRequestCall, 6000);
};

const saveSession = campaign => {
  try {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify({ campaign }));
  } catch {
    // ignore storage errors
  }
};

const clearSession = () => {
  try {
    sessionStorage.removeItem(SESSION_KEY);
  } catch {
    // ignore
  }
};

const closeDropdown = e => {
  if (!e.target.closest('[data-state-dropdown]')) {
    stateDropdownOpen.value = false;
  }
};

onMounted(async () => {
  try {
    const { data } = await dialerAccessesAPI.me();
    canAccess.value = data.can_access;
  } catch {
    canAccess.value = false;
  } finally {
    checkingAccess.value = false;
  }
  if (!canAccess.value) return;
  await Promise.all([
    store.dispatch('jabvoxDialer/fetchCampaigns'),
    store.dispatch('jabvoxDialer/fetchDialerStates'),
    store.dispatch('jabvoxManagementStates/fetchStates'),
  ]);
  emitter.on('jabvox.dialer.call_assigned', onCallAssigned);
  emitter.on('jabvox.dialer.call_ended', onCallEnded);
  document.addEventListener('click', closeDropdown);

  // Restore session after HMR / tab reload
  const raw = sessionStorage.getItem(SESSION_KEY);
  if (raw) {
    try {
      const session = JSON.parse(raw);
      try {
        await dialerAccessesAPI.heartbeat();
      } catch {
        // Agent state expired or was cleared — reconnect transparently
        await dialerAccessesAPI.connect(session.campaign.id);
      }
      activeCampaign.value = session.campaign;
      activeDialerState.value = null;
      connected.value = true;
      startHeartbeat();
      startRequestCallPolling();
    } catch {
      clearSession();
    }
  }
});

onBeforeUnmount(() => {
  emitter.off('jabvox.dialer.call_assigned', onCallAssigned);
  emitter.off('jabvox.dialer.call_ended', onCallEnded);
  document.removeEventListener('click', closeDropdown);
  stopHeartbeat();
  stopRequestCallPolling();
  clearWrapupTimer();
  if (connected.value) dialerAccessesAPI.disconnect().catch(() => {});
});

const onConnect = async campaign => {
  connecting.value = true;
  try {
    await dialerAccessesAPI.connect(campaign.id);
    activeCampaign.value = campaign;
    activeDialerState.value = null;
    connected.value = true;
    saveSession(campaign);
    startHeartbeat();
    startRequestCallPolling();
  } catch {
    // connect failed — stay disconnected
  } finally {
    connecting.value = false;
  }
};

const onDisconnect = async () => {
  stopHeartbeat();
  stopRequestCallPolling();
  clearWrapupTimer();
  clearSession();
  await dialerAccessesAPI.disconnect().catch(() => {});
  connected.value = false;
  store.dispatch('jabvoxDialer/fetchCampaigns');
  activeCampaign.value = null;
  activeDialerState.value = null;
  activeCall.value = null;
  dialingCall.value = null;
  lastCall.value = null;
  dialerStatusMessage.value = null;
  inWrapup.value = false;
  wrapupRemaining.value = 0;
  wrapupNote.value = '';
  wrapupStateId.value = null;
  stateDropdownOpen.value = false;
};

const setDialerState = async state => {
  activeDialerState.value = state;
  stateDropdownOpen.value = false;
  dialerAccessesAPI.updateState(state?.id ?? null).catch(() => {});
  if (state === null) {
    startRequestCallPolling();
  } else {
    stopRequestCallPolling();
  }
};
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <!-- Loading -->
    <div
      v-if="checkingAccess"
      class="flex-1 flex items-center justify-center text-n-slate-10 text-sm animate-pulse"
    >
      {{ t('JABVOX_PRODUCTS.LOADING') }}
    </div>

    <!-- Access denied -->
    <div v-else-if="!canAccess" class="flex-1 flex items-center justify-center">
      <div class="text-center space-y-3 max-w-sm">
        <div
          class="w-16 h-16 rounded-2xl bg-red-50 dark:bg-red-900/20 flex items-center justify-center mx-auto"
        >
          <span class="i-lucide-shield-off w-8 h-8 text-red-400" />
        </div>
        <h2 class="text-heading-2 text-n-slate-12">
          {{ t('JABVOX_DIALER.ACCESS_DENIED.TITLE') }}
        </h2>
        <p class="text-body-main text-n-slate-10">
          {{ t('JABVOX_DIALER.ACCESS_DENIED.DESCRIPTION') }}
        </p>
      </div>
    </div>

    <!-- ── Connected view ── -->
    <template v-else-if="connected && activeCampaign">
      <!-- Status bar -->
      <div
        class="shrink-0 h-14 px-6 flex items-center justify-between gap-4 border-b border-n-weak bg-n-surface-1"
      >
        <div class="flex items-center gap-3">
          <span
            class="relative flex h-2.5 w-2.5 shrink-0"
            :class="isAvailable ? 'visible' : 'invisible'"
          >
            <span
              class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"
            />
            <span
              class="relative inline-flex rounded-full h-2.5 w-2.5 bg-green-500"
            />
          </span>
          <span
            v-if="!isAvailable"
            class="h-2.5 w-2.5 rounded-full shrink-0"
            :style="{ backgroundColor: statusColor }"
          />
          <div>
            <p class="text-sm font-medium text-n-slate-12 leading-tight">
              {{ statusLabel }}
            </p>
            <p class="text-xs text-n-slate-10 leading-tight">
              {{ activeCampaign.name_jabvox }}
            </p>
          </div>
        </div>

        <!-- State dropdown button -->
        <div class="relative" data-state-dropdown>
          <button
            class="flex items-center gap-1.5 text-sm font-medium px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-surface-2 transition-colors"
            @click.stop="stateDropdownOpen = !stateDropdownOpen"
          >
            <span
              class="h-2 w-2 rounded-full shrink-0"
              :style="{ backgroundColor: statusColor }"
            />
            {{ statusLabel }}
            <i class="i-lucide-chevron-down w-3.5 h-3.5" />
          </button>

          <div
            v-if="stateDropdownOpen"
            class="absolute right-0 top-full mt-1 w-52 bg-white dark:bg-n-surface-2 rounded-xl border border-n-weak shadow-lg z-50 overflow-hidden"
          >
            <button
              v-if="activeDialerState"
              class="w-full text-left px-4 py-2.5 text-sm flex items-center gap-2.5 hover:bg-n-surface-2 dark:hover:bg-n-surface-3 text-green-600 dark:text-green-400"
              @click="setDialerState(null)"
            >
              <span class="h-2 w-2 rounded-full bg-green-500 shrink-0" />
              {{ t('JABVOX_DIALER.AVAILABLE') }}
            </button>

            <button
              v-for="ds in dialerStates"
              :key="ds.id"
              class="w-full text-left px-4 py-2.5 text-sm flex items-center gap-2.5 hover:bg-n-surface-2 dark:hover:bg-n-surface-3 text-n-slate-12"
              :class="
                activeDialerState?.id === ds.id
                  ? 'bg-n-surface-2 dark:bg-n-surface-3'
                  : ''
              "
              @click="setDialerState(ds)"
            >
              <span
                class="h-2 w-2 rounded-full shrink-0"
                :style="{ backgroundColor: ds.color }"
              />
              {{ ds.name }}
            </button>

            <div class="border-t border-n-weak mx-2 my-1" />

            <button
              class="w-full text-left px-4 py-2.5 text-sm flex items-center gap-2.5 text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20"
              @click="onDisconnect"
            >
              <i class="i-lucide-phone-off w-3.5 h-3.5 shrink-0" />
              {{ t('JABVOX_DIALER.DISCONNECT') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Dialing card (call initiated, waiting for agent connection) -->
      <div
        v-if="dialingCall && !activeCall"
        class="shrink-0 mx-6 mt-4 rounded-xl bg-n-surface-2 border border-n-weak px-4 py-3"
      >
        <div class="flex items-center gap-3">
          <span class="i-lucide-phone-outgoing w-5 h-5 text-n-slate-10 shrink-0 animate-pulse" />
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-n-slate-12 truncate">
              {{ t('JABVOX_DIALER.DIALING') }}
            </p>
            <p class="text-xs text-n-slate-10">{{ t('JABVOX_DIALER.DIALING_HINT') }}</p>
          </div>
        </div>
      </div>

      <!-- Active call card -->
      <div
        v-if="activeCall"
        class="shrink-0 mx-6 mt-4 rounded-xl bg-woot-50 dark:bg-woot-900/20 border border-woot-200 dark:border-woot-700 px-4 py-3 space-y-2.5"
      >
        <!-- Header row: name + actions -->
        <div class="flex items-start gap-3">
          <span class="i-lucide-phone-call w-5 h-5 text-woot-600 dark:text-woot-400 shrink-0 animate-pulse mt-0.5" />
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-n-slate-12 truncate">
              {{ activeCall.contact_name || activeCall.contact_phone }}
              <span v-if="activeCall.lead_number" class="ml-1.5 text-xs font-normal text-n-slate-8">#{{ activeCall.lead_number }}</span>
            </p>
          </div>
          <div class="shrink-0 flex gap-1.5">
            <button
              class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg bg-red-500 text-white hover:bg-red-600 transition-colors"
              @click="onEndCall"
            >
              <i class="i-lucide-phone-off w-3.5 h-3.5" />
              {{ t('JABVOX_DIALER.CALL.END') }}
            </button>
            <button
              v-if="activeCall.conversation_id"
              class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-woot-300 text-woot-600 hover:bg-woot-100 dark:hover:bg-woot-900/40 transition-colors"
              @click="openConversation"
            >
              <i class="i-lucide-external-link w-3.5 h-3.5" />
              {{ t('JABVOX_DIALER.CALL.OPEN_CONVERSATION') }}
            </button>
          </div>
        </div>

        <!-- Contact + lead details grid -->
        <div class="grid grid-cols-2 gap-x-4 gap-y-1 pl-8">
          <p class="text-xs text-n-slate-10 truncate flex items-center gap-1">
            <i class="i-lucide-phone w-3 h-3 shrink-0 text-n-slate-8" />
            {{ activeCall.contact_phone }}
          </p>
          <p v-if="activeCall.contact_email" class="text-xs text-n-slate-10 truncate flex items-center gap-1">
            <i class="i-lucide-mail w-3 h-3 shrink-0 text-n-slate-8" />
            {{ activeCall.contact_email }}
          </p>
          <p v-if="activeCall.contact_country" class="text-xs text-n-slate-10 truncate flex items-center gap-1">
            <i class="i-lucide-globe w-3 h-3 shrink-0 text-n-slate-8" />
            {{ activeCall.contact_country }}
          </p>
          <p v-if="activeCall.affiliate_name" class="text-xs text-n-slate-10 truncate flex items-center gap-1">
            <i class="i-lucide-users w-3 h-3 shrink-0 text-n-slate-8" />
            {{ activeCall.affiliate_name }}
          </p>
          <p v-if="activeCall.campaign_name" class="text-xs text-n-slate-10 truncate flex items-center gap-1">
            <i class="i-lucide-tag w-3 h-3 shrink-0 text-n-slate-8" />
            {{ activeCall.campaign_name }}
          </p>
        </div>

        <!-- Gestión history -->
        <div
          v-if="activeCall.management_history?.length"
          class="pl-8 pt-2 mt-1 border-t border-woot-100 dark:border-woot-800 space-y-1"
        >
          <p class="text-xs font-medium text-n-slate-9">{{ t('JABVOX_DIALER.HISTORY.TITLE') }}</p>
          <div class="space-y-0.5 max-h-20 overflow-y-auto pr-1">
            <div
              v-for="(g, i) in activeCall.management_history"
              :key="i"
              class="flex items-start gap-1.5"
            >
              <span
                class="inline-block h-2 w-2 rounded-full shrink-0 mt-0.5"
                :style="{ backgroundColor: g.state_color || '#6b7280' }"
              />
              <div class="min-w-0 text-xs leading-tight">
                <span class="font-medium text-n-slate-11">{{ g.state_name }}</span>
                <span v-if="g.note" class="text-n-slate-8 ml-1">— {{ g.note }}</span>
                <span class="text-n-slate-7 ml-1">{{ g.created_at }}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Gestión note (fill during call, persists into wrapup) -->
        <div class="pl-8 pt-2 mt-1 border-t border-woot-100 dark:border-woot-800 space-y-2">
          <div v-if="managementStates.length > 0" class="flex flex-wrap gap-1.5">
            <button
              v-for="s in managementStates"
              :key="s.id"
              class="text-xs px-2.5 py-1 rounded-full border transition-colors"
              :class="wrapupStateId === s.id ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-surface-2'"
              :style="wrapupStateId === s.id ? { backgroundColor: s.color_jabvox || '#6b7280', borderColor: s.color_jabvox || '#6b7280' } : {}"
              @click="wrapupStateId = wrapupStateId === s.id ? null : s.id"
            >
              {{ s.name_jabvox }}
            </button>
          </div>
          <textarea
            v-model="wrapupNote"
            rows="2"
            class="w-full rounded-lg border border-n-weak bg-white dark:bg-n-surface-2 px-3 py-2 text-xs text-n-slate-12 placeholder:text-n-slate-8 resize-none focus:outline-none focus:ring-1 focus:ring-woot-400"
            :placeholder="t('JABVOX_DIALER.WRAPUP.NOTE_PLACEHOLDER')"
          />
          <p v-if="!activeCall?.conversation_id" class="text-xs text-n-slate-8">
            {{ t('JABVOX_DIALER.WRAPUP.NO_CONVERSATION') }}
          </p>
        </div>
      </div>

      <!-- Wrapup panel -->
      <div
        v-if="inWrapup && !activeCall"
        class="shrink-0 mx-6 mt-4 rounded-xl border border-amber-200 dark:border-amber-700 bg-amber-50 dark:bg-amber-900/20 px-4 py-3 space-y-3"
      >
        <!-- Timer row -->
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <i class="i-lucide-clock w-4 h-4 text-amber-600 dark:text-amber-400" />
            <span class="text-sm font-medium text-amber-800 dark:text-amber-200">
              {{ t('JABVOX_DIALER.WRAPUP.TITLE') }}
            </span>
            <span class="text-sm font-bold text-amber-700 dark:text-amber-300 tabular-nums">
              {{ wrapupRemaining }}s
            </span>
          </div>
          <button
            class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg bg-woot-500 text-white hover:bg-woot-600 transition-colors"
            :disabled="isSavingNote"
            @click="saveWrapupNote().then(endWrapup)"
          >
            <i class="i-lucide-skip-forward w-3.5 h-3.5" />
            {{ t('JABVOX_DIALER.WRAPUP.NEXT') }}
          </button>
        </div>

        <!-- Progress bar -->
        <div class="w-full h-1 bg-amber-200 dark:bg-amber-800 rounded-full overflow-hidden">
          <div
            class="h-full bg-amber-500 rounded-full transition-all duration-1000 ease-linear"
            :style="{ width: `${(wrapupRemaining / (activeCampaign?.wrapup_time_jabvox || 30)) * 100}%` }"
          />
        </div>

        <!-- Contact summary -->
        <div v-if="lastCall" class="space-y-0.5">
          <p class="text-xs font-semibold text-n-slate-12 truncate">
            {{ lastCall.contact_name || lastCall.contact_phone }}
            <span v-if="lastCall.lead_number" class="ml-1 font-normal text-n-slate-8">#{{ lastCall.lead_number }}</span>
          </p>
          <div class="flex flex-wrap gap-x-3 gap-y-0.5">
            <span class="text-xs text-n-slate-10 flex items-center gap-0.5">
              <i class="i-lucide-phone w-3 h-3" />{{ lastCall.contact_phone }}
            </span>
            <span v-if="lastCall.contact_email" class="text-xs text-n-slate-10 flex items-center gap-0.5">
              <i class="i-lucide-mail w-3 h-3" />{{ lastCall.contact_email }}
            </span>
            <span v-if="lastCall.affiliate_name" class="text-xs text-n-slate-10 flex items-center gap-0.5">
              <i class="i-lucide-users w-3 h-3" />{{ lastCall.affiliate_name }}
            </span>
            <span v-if="lastCall.campaign_name" class="text-xs text-n-slate-10 flex items-center gap-0.5">
              <i class="i-lucide-tag w-3 h-3" />{{ lastCall.campaign_name }}
            </span>
          </div>
        </div>

        <!-- Gestión history in wrapup -->
        <div v-if="lastCall?.management_history?.length" class="space-y-1">
          <p class="text-xs font-medium text-n-slate-9">{{ t('JABVOX_DIALER.HISTORY.TITLE') }}</p>
          <div class="space-y-0.5 max-h-24 overflow-y-auto rounded-lg bg-white dark:bg-n-surface-3 px-2 py-1.5 border border-n-weak">
            <div
              v-for="(g, i) in lastCall.management_history"
              :key="i"
              class="flex items-start gap-1.5"
            >
              <span
                class="inline-block h-2 w-2 rounded-full shrink-0 mt-0.5"
                :style="{ backgroundColor: g.state_color || '#6b7280' }"
              />
              <div class="min-w-0 flex-1 text-xs leading-tight">
                <span class="font-medium text-n-slate-11">{{ g.state_name }}</span>
                <span v-if="g.note" class="text-n-slate-8 ml-1">— {{ g.note }}</span>
                <span class="text-n-slate-7 ml-1">{{ g.created_at }}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Gestión note form -->
        <div class="space-y-2">
          <!-- Management state selector -->
          <div v-if="managementStates.length > 0" class="flex flex-wrap gap-1.5">
            <button
              v-for="s in managementStates"
              :key="s.id"
              class="text-xs px-2.5 py-1 rounded-full border transition-colors"
              :class="wrapupStateId === s.id
                ? 'text-white border-transparent'
                : 'border-n-weak text-n-slate-11 hover:bg-n-surface-2'"
              :style="wrapupStateId === s.id ? { backgroundColor: s.color_jabvox || '#6b7280', borderColor: s.color_jabvox || '#6b7280' } : {}"
              @click="wrapupStateId = wrapupStateId === s.id ? null : s.id"
            >
              {{ s.name_jabvox }}
            </button>
          </div>

          <!-- Note textarea -->
          <textarea
            v-model="wrapupNote"
            rows="2"
            class="w-full rounded-lg border border-n-weak bg-white dark:bg-n-surface-2 px-3 py-2 text-xs text-n-slate-12 placeholder:text-n-slate-8 resize-none focus:outline-none focus:ring-1 focus:ring-woot-400"
            :placeholder="t('JABVOX_DIALER.WRAPUP.NOTE_PLACEHOLDER')"
          />
          <p v-if="!lastCall?.conversation_id" class="text-xs text-n-slate-8">
            {{ t('JABVOX_DIALER.WRAPUP.NO_CONVERSATION') }}
          </p>
        </div>
      </div>

      <!-- Main connected area -->
      <div class="flex-1 flex items-center justify-center">
        <div class="text-center space-y-4">
          <div
            v-if="isAvailable"
            class="w-24 h-24 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center mx-auto"
          >
            <span class="i-lucide-phone-incoming w-10 h-10 text-green-500 animate-pulse" />
          </div>
          <div
            v-else-if="dialingCall && !activeCall"
            class="w-24 h-24 rounded-full bg-n-surface-2 flex items-center justify-center mx-auto"
          >
            <span class="i-lucide-phone-outgoing w-10 h-10 text-n-slate-10 animate-pulse" />
          </div>
          <div
            v-else-if="activeCall"
            class="w-24 h-24 rounded-full bg-woot-100 dark:bg-woot-900/30 flex items-center justify-center mx-auto"
          >
            <span class="i-lucide-phone-call w-10 h-10 text-woot-500 animate-pulse" />
          </div>
          <div
            v-else-if="inWrapup"
            class="w-24 h-24 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center mx-auto"
          >
            <span class="i-lucide-clock w-10 h-10 text-amber-500" />
          </div>
          <div
            v-else
            class="w-24 h-24 rounded-full flex items-center justify-center mx-auto"
            :style="{ backgroundColor: `${statusColor}1a` }"
          >
            <span class="i-lucide-pause-circle w-10 h-10" :style="{ color: statusColor }" />
          </div>

          <div class="space-y-1.5">
            <p class="text-base font-semibold text-n-slate-12">
              <template v-if="activeCall">
                {{ t('JABVOX_DIALER.CALL.IN_CALL') }}
              </template>
              <template v-else-if="dialingCall">
                {{ t('JABVOX_DIALER.DIALING') }}
              </template>
              <template v-else-if="inWrapup">
                {{ t('JABVOX_DIALER.WRAPUP.TITLE') }}
              </template>
              <template v-else-if="isAvailable">
                {{ t('JABVOX_DIALER.WAITING_CALL') }}
              </template>
              <template v-else>
                {{ t('JABVOX_DIALER.NOT_AVAILABLE') }}
              </template>
            </p>
            <p class="text-sm text-n-slate-10">
              <span
                v-if="activeCall"
                class="font-medium text-woot-600 dark:text-woot-400"
              >
                {{ activeCall.contact_name || activeCall.contact_phone }}
              </span>
              <span v-else-if="dialingCall" class="font-medium text-n-slate-11">
                {{ dialingCall.contact_name || dialingCall.contact_phone }}
              </span>
              <span
                v-else-if="!isAvailable && !inWrapup"
                class="font-medium"
                :style="{ color: statusColor }"
              >
                {{ activeDialerState?.name }}
              </span>
              <span v-else>{{ activeCampaign.name_jabvox }}</span>
            </p>
            <p
              v-if="dialerStatusMessage && isAvailable && !activeCall"
              class="text-xs text-amber-600 dark:text-amber-400 mt-1"
            >
              {{ dialerStatusMessage }}
            </p>
            <button
              v-if="!isAvailable && !activeCall"
              class="mt-3 text-xs font-medium px-3 py-1.5 rounded-lg border border-green-300 text-green-700 hover:bg-green-50 dark:hover:bg-green-900/20 transition-colors"
              @click="setDialerState(null)"
            >
              {{ t('JABVOX_DIALER.AVAILABLE') }}
            </button>
          </div>
        </div>
      </div>
    </template>

    <!-- ── Campaign picker ── -->
    <template v-else>
      <div class="shrink-0 border-b border-n-weak bg-n-surface-1 px-6 py-5">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ t('JABVOX_DIALER.TITLE') }}
        </h1>
        <p class="text-body-main text-n-slate-10 mt-0.5">
          {{ t('JABVOX_DIALER.MY_CAMPAIGNS_HINT') }}
        </p>
      </div>

      <div class="flex-1 overflow-y-auto p-6">
        <div
          v-if="uiFlags.isFetchingCampaigns"
          class="text-sm text-n-slate-10 text-center py-16 animate-pulse"
        >
          {{ t('JABVOX_PRODUCTS.LOADING') }}
        </div>
        <div
          v-else-if="!myCampaigns.length"
          class="flex flex-col items-center justify-center py-20 gap-4"
        >
          <div
            class="w-16 h-16 rounded-2xl bg-n-surface-2 flex items-center justify-center"
          >
            <i class="i-lucide-phone-off w-8 h-8 text-n-slate-8" />
          </div>
          <p class="text-body-main text-n-slate-10 text-center max-w-xs">
            {{ t('JABVOX_DIALER.NO_ASSIGNED_CAMPAIGNS') }}
          </p>
        </div>
        <div v-else class="max-w-xl mx-auto space-y-3">
          <div
            v-for="c in myCampaigns"
            :key="c.id"
            class="bg-white dark:bg-n-surface-2 rounded-2xl border border-n-weak p-5 flex items-center justify-between gap-4"
          >
            <div class="min-w-0">
              <p class="text-sm font-semibold text-n-slate-12 truncate">
                {{ c.name_jabvox }}
              </p>
              <p class="text-xs text-n-slate-10 mt-0.5">
                {{ c.leads_count_jabvox }}
                {{ t('JABVOX_DIALER.STATS.LEADS') }}
              </p>
            </div>
            <div class="shrink-0">
              <button
                class="flex items-center gap-1.5 text-sm font-medium px-4 py-2 rounded-lg bg-woot-500 text-white hover:bg-woot-600 disabled:opacity-50 transition-colors"
                :disabled="connecting"
                @click="onConnect(c)"
              >
                <i class="i-lucide-plug w-4 h-4" />
                {{ t('JABVOX_DIALER.CONNECT') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
