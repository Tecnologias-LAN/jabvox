<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import {
  dialerAccessesAPI,
  dialerCallLogsAPI,
} from 'dashboard/api/jabvox/dialer';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';
import messageAPI from 'dashboard/api/inbox/message';
import ManagementQuestionsForm from 'dashboard/components/jabvox/managementStates/ManagementQuestionsForm.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import {
  isManagementValid,
  buildManagementContentAttributes,
} from 'dashboard/composables/jabvox/useManagementState';
import { useAlert } from 'dashboard/composables';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const campaigns = useMapGetter('jabvoxDialer/getCampaigns');
const dialerStates = useMapGetter('jabvoxDialer/getDialerStates');
const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');
const uiFlags = useMapGetter('jabvoxDialer/getUIFlags');
const currentUserId = useMapGetter('getCurrentUserID');

const SESSION_KEY = 'jabvox_dialer_session';

// Decorative glyphs bound so they don't count as bare template strings.
const SECONDS_SUFFIX = 's';
const LEAD_PREFIX = '#';
const NOTE_SEPARATOR = '— ';

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
const managementAnswers = ref({});
const isSavingNote = ref(false);
const typifications = ref([]);
const wrapupTypificationId = ref(null);

const selectedManagementState = computed(() =>
  (managementStates.value || []).find(s => s.id === wrapupStateId.value)
);
let heartbeatTimer = null;
let requestCallTimer = null;
let wrapupTimer = null;

const clearWrapupTimer = () => {
  if (wrapupTimer) {
    clearInterval(wrapupTimer);
    wrapupTimer = null;
  }
};

const stopRequestCallPolling = () => {
  if (requestCallTimer) {
    clearInterval(requestCallTimer);
    requestCallTimer = null;
  }
};

const doRequestCall = async () => {
  if (
    !connected.value ||
    activeDialerState.value !== null ||
    activeCall.value ||
    dialingCall.value ||
    inWrapup.value
  )
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
  activeCall.value = {
    ...data,
    dialer_contact_id: data.dialer_contact_id || pendingId,
  };
  inWrapup.value = false;
  clearWrapupTimer();
};

const endWrapup = () => {
  clearWrapupTimer();
  inWrapup.value = false;
  wrapupRemaining.value = 0;
  lastCall.value = null;
  wrapupNote.value = '';
  wrapupStateId.value = null;
  wrapupTypificationId.value = null;
  managementAnswers.value = {};
  if (connected.value && activeDialerState.value === null) {
    // Unpause agent in Asterisk queue before requesting next call
    dialerAccessesAPI.updateState(null).catch(() => {});
    startRequestCallPolling();
  }
};

// Persists the chosen typification on the dialer call log (links to CDR + pipelines).
const saveTypification = async () => {
  const dialerContactId = lastCall.value?.dialer_contact_id;
  if (!dialerContactId || !wrapupTypificationId.value) return;
  try {
    await dialerCallLogsAPI.typify({
      contact_id: dialerContactId,
      typification_id: wrapupTypificationId.value,
    });
  } catch {
    // best-effort — the note already saved
  }
};

const saveWrapupNote = async () => {
  const convId = lastCall.value?.conversation_id;
  const stateObj = selectedManagementState.value;
  const note = wrapupNote.value.trim() || stateObj?.name_jabvox || '';
  if (!convId || !note || isSavingNote.value) return;
  if (
    stateObj &&
    !isManagementValid(stateObj, managementAnswers.value, wrapupNote.value)
  ) {
    useAlert(t('JABVOX_MANAGEMENT_STATES.QUESTIONS.INCOMPLETE'));
    return;
  }
  const payload = {
    conversationId: convId,
    message: note,
    private: true,
    echo_id: `jabvox_dialer_${Date.now()}`,
  };
  if (stateObj) {
    payload.contentAttributes = buildManagementContentAttributes(
      stateObj,
      managementAnswers.value
    );
  }
  isSavingNote.value = true;
  try {
    await messageAPI.create(payload);
    await saveTypification();
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
  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: convId },
  });
};

const onEndCall = () => {
  const dialerContactId =
    activeCall.value?.dialer_contact_id || dialingCall.value?.dialer_contact_id;
  lastCall.value = activeCall.value || dialingCall.value || lastCall.value;
  activeCall.value = null;
  dialingCall.value = null;
  if (dialerContactId)
    dialerAccessesAPI.endCall(dialerContactId).catch(() => {});
  startWrapup();
};

const onCallEnded = () => {
  if (!activeCall.value && !dialingCall.value) return;
  const dialerContactId =
    activeCall.value?.dialer_contact_id || dialingCall.value?.dialer_contact_id;
  lastCall.value = activeCall.value || dialingCall.value || lastCall.value;
  activeCall.value = null;
  dialingCall.value = null;
  if (dialerContactId)
    dialerAccessesAPI.endCall(dialerContactId).catch(() => {});
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
  try {
    const { data } = await typificationsAPI.getAll(true);
    typifications.value = data.typifications || data || [];
  } catch {
    typifications.value = [];
  }
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
  managementAnswers.value = {};
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
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-background">
    <!-- Loading -->
    <div
      v-if="checkingAccess"
      class="flex-1 flex items-center justify-center gap-2 text-n-slate-11 text-sm"
    >
      <Spinner :size="18" />
      {{ t('JABVOX_PRODUCTS.LOADING') }}
    </div>

    <!-- Access denied -->
    <div v-else-if="!canAccess" class="flex-1 flex items-center justify-center">
      <div class="text-center space-y-3 max-w-sm">
        <div
          class="size-16 rounded-2xl bg-n-ruby-3 flex items-center justify-center mx-auto"
        >
          <span class="i-lucide-shield-off size-8 text-n-ruby-11" />
        </div>
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{ t('JABVOX_DIALER.ACCESS_DENIED.TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_DIALER.ACCESS_DENIED.DESCRIPTION') }}
        </p>
      </div>
    </div>

    <!-- ── Connected view ── -->
    <template v-else-if="connected && activeCampaign">
      <!-- Status bar -->
      <div
        class="shrink-0 h-16 px-4 sm:px-6 flex items-center justify-between gap-4 border-b border-n-weak bg-n-solid-1"
      >
        <div class="flex items-center gap-3 min-w-0">
          <span
            class="relative flex size-2.5 shrink-0"
            :class="isAvailable ? 'visible' : 'invisible'"
          >
            <span
              class="animate-ping absolute inline-flex size-full rounded-full bg-n-teal-9 opacity-75"
            />
            <span
              class="relative inline-flex rounded-full size-2.5 bg-n-teal-9"
            />
          </span>
          <span
            v-if="!isAvailable"
            class="size-2.5 rounded-full shrink-0"
            :style="{ backgroundColor: statusColor }"
          />
          <div class="min-w-0">
            <p
              class="text-sm font-semibold text-n-slate-12 leading-tight truncate"
            >
              {{ statusLabel }}
            </p>
            <p class="text-xs text-n-slate-10 leading-tight truncate">
              {{ activeCampaign.name_jabvox }}
            </p>
          </div>
        </div>

        <!-- State dropdown button -->
        <div class="relative shrink-0" data-state-dropdown>
          <button
            class="flex items-center gap-1.5 text-sm font-medium px-3 py-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
            @click.stop="stateDropdownOpen = !stateDropdownOpen"
          >
            <span
              class="size-2 rounded-full shrink-0"
              :style="{ backgroundColor: statusColor }"
            />
            {{ statusLabel }}
            <span class="i-lucide-chevron-down size-3.5" />
          </button>

          <div
            v-if="stateDropdownOpen"
            class="absolute right-0 top-full mt-1.5 w-56 bg-n-solid-1 rounded-xl border border-n-weak shadow-lg z-50 overflow-hidden py-1"
          >
            <button
              v-if="activeDialerState"
              class="w-full text-left px-4 py-2.5 text-sm flex items-center gap-2.5 hover:bg-n-alpha-1 text-n-teal-11"
              @click="setDialerState(null)"
            >
              <span class="size-2 rounded-full bg-n-teal-9 shrink-0" />
              {{ t('JABVOX_DIALER.AVAILABLE') }}
            </button>

            <button
              v-for="ds in dialerStates"
              :key="ds.id"
              class="w-full text-left px-4 py-2.5 text-sm flex items-center gap-2.5 hover:bg-n-alpha-1 text-n-slate-12"
              :class="activeDialerState?.id === ds.id ? 'bg-n-alpha-2' : ''"
              @click="setDialerState(ds)"
            >
              <span
                class="size-2 rounded-full shrink-0"
                :style="{ backgroundColor: ds.color }"
              />
              {{ ds.name }}
            </button>

            <div class="border-t border-n-weak mx-2 my-1" />

            <button
              class="w-full text-left px-4 py-2.5 text-sm flex items-center gap-2.5 text-n-ruby-11 hover:bg-n-ruby-3"
              @click="onDisconnect"
            >
              <span class="i-lucide-phone-off size-3.5 shrink-0" />
              {{ t('JABVOX_DIALER.DISCONNECT') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Floating call/wrapup cards -->
      <div class="shrink-0 w-full max-w-3xl mx-auto px-4 sm:px-6">
        <!-- Dialing card (call initiated, waiting for agent connection) -->
        <div
          v-if="dialingCall && !activeCall"
          class="mt-4 rounded-2xl bg-n-alpha-1 border border-n-weak px-4 py-3 shadow-sm"
        >
          <div class="flex items-center gap-3">
            <span
              class="i-lucide-phone-outgoing size-5 text-n-slate-10 shrink-0 animate-pulse"
            />
            <div class="min-w-0 flex-1">
              <p class="text-sm font-semibold text-n-slate-12 truncate">
                {{ t('JABVOX_DIALER.DIALING') }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{ t('JABVOX_DIALER.DIALING_HINT') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Active call card -->
        <div
          v-if="activeCall"
          class="mt-4 rounded-2xl bg-n-alpha-2 border border-n-brand/30 px-4 py-3 space-y-2.5 shadow-sm"
        >
          <!-- Header row: name + actions -->
          <div class="flex items-start gap-3">
            <span
              class="i-lucide-phone-call size-5 text-n-brand shrink-0 animate-pulse mt-0.5"
            />
            <div class="min-w-0 flex-1">
              <p class="text-sm font-semibold text-n-slate-12 truncate">
                {{ activeCall.contact_name || activeCall.contact_phone }}
                <span
                  v-if="activeCall.lead_number"
                  class="ml-1.5 text-xs font-normal text-n-slate-10"
                  >{{ LEAD_PREFIX }}{{ activeCall.lead_number }}</span
                >
              </p>
            </div>
            <div class="shrink-0 flex gap-1.5">
              <Button
                :label="t('JABVOX_DIALER.CALL.END')"
                icon="i-lucide-phone-off"
                color="ruby"
                size="sm"
                @click="onEndCall"
              />
              <Button
                v-if="activeCall.conversation_id"
                :label="t('JABVOX_DIALER.CALL.OPEN_CONVERSATION')"
                icon="i-lucide-external-link"
                variant="outline"
                color="slate"
                size="sm"
                @click="openConversation"
              />
            </div>
          </div>

          <!-- Contact + lead details grid -->
          <div class="grid grid-cols-2 gap-x-4 gap-y-1 pl-8">
            <p class="text-xs text-n-slate-11 truncate flex items-center gap-1">
              <span class="i-lucide-phone size-3 shrink-0 text-n-slate-9" />
              {{ activeCall.contact_phone }}
            </p>
            <p
              v-if="activeCall.contact_email"
              class="text-xs text-n-slate-11 truncate flex items-center gap-1"
            >
              <span class="i-lucide-mail size-3 shrink-0 text-n-slate-9" />
              {{ activeCall.contact_email }}
            </p>
            <p
              v-if="activeCall.contact_country"
              class="text-xs text-n-slate-11 truncate flex items-center gap-1"
            >
              <span class="i-lucide-globe size-3 shrink-0 text-n-slate-9" />
              {{ activeCall.contact_country }}
            </p>
            <p
              v-if="activeCall.affiliate_name"
              class="text-xs text-n-slate-11 truncate flex items-center gap-1"
            >
              <span class="i-lucide-users size-3 shrink-0 text-n-slate-9" />
              {{ activeCall.affiliate_name }}
            </p>
            <p
              v-if="activeCall.campaign_name"
              class="text-xs text-n-slate-11 truncate flex items-center gap-1"
            >
              <span class="i-lucide-tag size-3 shrink-0 text-n-slate-9" />
              {{ activeCall.campaign_name }}
            </p>
          </div>

          <!-- Gestión history -->
          <div
            v-if="activeCall.management_history?.length"
            class="pl-8 pt-2 mt-1 border-t border-n-weak space-y-1"
          >
            <p class="text-xs font-medium text-n-slate-10">
              {{ t('JABVOX_DIALER.HISTORY.TITLE') }}
            </p>
            <div class="space-y-0.5 max-h-20 overflow-y-auto pr-1">
              <div
                v-for="(g, i) in activeCall.management_history"
                :key="i"
                class="flex items-start gap-1.5"
              >
                <span
                  class="inline-block size-2 rounded-full shrink-0 mt-0.5"
                  :style="{ backgroundColor: g.state_color || '#6b7280' }"
                />
                <div class="min-w-0 text-xs leading-tight">
                  <span class="font-medium text-n-slate-11">{{
                    g.state_name
                  }}</span>
                  <span v-if="g.note" class="text-n-slate-10 ml-1">
                    {{ NOTE_SEPARATOR }}{{ g.note }}
                  </span>
                  <span class="text-n-slate-9 ml-1">{{ g.created_at }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Gestión note (fill during call, persists into wrapup) -->
          <div class="pl-8 pt-2 mt-1 border-t border-n-weak space-y-2">
            <div
              v-if="managementStates.length > 0"
              class="flex flex-wrap gap-1.5"
            >
              <button
                v-for="s in managementStates"
                :key="s.id"
                class="text-xs px-2.5 py-1 rounded-full border transition-colors"
                :class="
                  wrapupStateId === s.id
                    ? 'text-white border-transparent'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                "
                :style="
                  wrapupStateId === s.id
                    ? {
                        backgroundColor: s.color_jabvox || '#6b7280',
                        borderColor: s.color_jabvox || '#6b7280',
                      }
                    : {}
                "
                @click="wrapupStateId = wrapupStateId === s.id ? null : s.id"
              >
                {{ s.name_jabvox }}
              </button>
            </div>
            <ManagementQuestionsForm
              v-if="selectedManagementState"
              v-model="managementAnswers"
              :state="selectedManagementState"
            />
            <select
              v-if="typifications.length"
              v-model="wrapupTypificationId"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            >
              <option :value="null">
                {{ t('JABVOX_DIALER.WRAPUP.TYPIFICATION_PLACEHOLDER') }}
              </option>
              <option v-for="tp in typifications" :key="tp.id" :value="tp.id">
                {{ tp.name }}
              </option>
            </select>
            <textarea
              v-model="wrapupNote"
              rows="2"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12 placeholder:text-n-slate-9 resize-none focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('JABVOX_DIALER.WRAPUP.NOTE_PLACEHOLDER')"
            />
            <p
              v-if="!activeCall?.conversation_id"
              class="text-xs text-n-slate-10"
            >
              {{ t('JABVOX_DIALER.WRAPUP.NO_CONVERSATION') }}
            </p>
          </div>
        </div>

        <!-- Wrapup panel -->
        <div
          v-if="inWrapup && !activeCall"
          class="mt-4 rounded-2xl border border-n-amber-6 bg-n-amber-3 px-4 py-3 space-y-3 shadow-sm"
        >
          <!-- Timer row -->
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="i-lucide-clock size-4 text-n-amber-11" />
              <span class="text-sm font-medium text-n-amber-11">
                {{ t('JABVOX_DIALER.WRAPUP.TITLE') }}
              </span>
              <span class="text-sm font-bold text-n-amber-11 tabular-nums">
                {{ wrapupRemaining }}{{ SECONDS_SUFFIX }}
              </span>
            </div>
            <Button
              :label="t('JABVOX_DIALER.WRAPUP.NEXT')"
              icon="i-lucide-skip-forward"
              size="sm"
              :is-loading="isSavingNote"
              @click="saveWrapupNote().then(endWrapup)"
            />
          </div>

          <!-- Progress bar -->
          <div class="w-full h-1 bg-n-amber-6 rounded-full overflow-hidden">
            <div
              class="h-full bg-n-amber-9 rounded-full transition-all duration-1000 ease-linear"
              :style="{
                width: `${(wrapupRemaining / (activeCampaign?.wrapup_time_jabvox || 30)) * 100}%`,
              }"
            />
          </div>

          <!-- Contact summary -->
          <div v-if="lastCall" class="space-y-0.5">
            <p class="text-xs font-semibold text-n-slate-12 truncate">
              {{ lastCall.contact_name || lastCall.contact_phone }}
              <span
                v-if="lastCall.lead_number"
                class="ml-1 font-normal text-n-slate-10"
                >{{ LEAD_PREFIX }}{{ lastCall.lead_number }}</span
              >
            </p>
            <div class="flex flex-wrap gap-x-3 gap-y-0.5">
              <span class="text-xs text-n-slate-11 flex items-center gap-0.5">
                <span class="i-lucide-phone size-3" />{{
                  lastCall.contact_phone
                }}
              </span>
              <span
                v-if="lastCall.contact_email"
                class="text-xs text-n-slate-11 flex items-center gap-0.5"
              >
                <span class="i-lucide-mail size-3" />{{
                  lastCall.contact_email
                }}
              </span>
              <span
                v-if="lastCall.affiliate_name"
                class="text-xs text-n-slate-11 flex items-center gap-0.5"
              >
                <span class="i-lucide-users size-3" />{{
                  lastCall.affiliate_name
                }}
              </span>
              <span
                v-if="lastCall.campaign_name"
                class="text-xs text-n-slate-11 flex items-center gap-0.5"
              >
                <span class="i-lucide-tag size-3" />{{ lastCall.campaign_name }}
              </span>
            </div>
          </div>

          <!-- Gestión history in wrapup -->
          <div v-if="lastCall?.management_history?.length" class="space-y-1">
            <p class="text-xs font-medium text-n-slate-10">
              {{ t('JABVOX_DIALER.HISTORY.TITLE') }}
            </p>
            <div
              class="space-y-0.5 max-h-24 overflow-y-auto rounded-lg bg-n-solid-1 px-2 py-1.5 border border-n-weak"
            >
              <div
                v-for="(g, i) in lastCall.management_history"
                :key="i"
                class="flex items-start gap-1.5"
              >
                <span
                  class="inline-block size-2 rounded-full shrink-0 mt-0.5"
                  :style="{ backgroundColor: g.state_color || '#6b7280' }"
                />
                <div class="min-w-0 flex-1 text-xs leading-tight">
                  <span class="font-medium text-n-slate-11">{{
                    g.state_name
                  }}</span>
                  <span v-if="g.note" class="text-n-slate-10 ml-1">
                    {{ NOTE_SEPARATOR }}{{ g.note }}
                  </span>
                  <span class="text-n-slate-9 ml-1">{{ g.created_at }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Gestión note form -->
          <div class="space-y-2">
            <!-- Management state selector -->
            <div
              v-if="managementStates.length > 0"
              class="flex flex-wrap gap-1.5"
            >
              <button
                v-for="s in managementStates"
                :key="s.id"
                class="text-xs px-2.5 py-1 rounded-full border transition-colors"
                :class="
                  wrapupStateId === s.id
                    ? 'text-white border-transparent'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                "
                :style="
                  wrapupStateId === s.id
                    ? {
                        backgroundColor: s.color_jabvox || '#6b7280',
                        borderColor: s.color_jabvox || '#6b7280',
                      }
                    : {}
                "
                @click="wrapupStateId = wrapupStateId === s.id ? null : s.id"
              >
                {{ s.name_jabvox }}
              </button>
            </div>

            <ManagementQuestionsForm
              v-if="selectedManagementState"
              v-model="managementAnswers"
              :state="selectedManagementState"
            />

            <!-- Note textarea -->
            <textarea
              v-model="wrapupNote"
              rows="2"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12 placeholder:text-n-slate-9 resize-none focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="t('JABVOX_DIALER.WRAPUP.NOTE_PLACEHOLDER')"
            />
            <p
              v-if="!lastCall?.conversation_id"
              class="text-xs text-n-slate-10"
            >
              {{ t('JABVOX_DIALER.WRAPUP.NO_CONVERSATION') }}
            </p>
          </div>
        </div>
      </div>
      <!-- /Floating call/wrapup cards -->

      <!-- Main connected area -->
      <div class="flex-1 flex items-center justify-center p-6">
        <div class="text-center space-y-4">
          <div
            v-if="isAvailable"
            class="size-24 rounded-full bg-n-teal-3 flex items-center justify-center mx-auto"
          >
            <span
              class="i-lucide-phone-incoming size-10 text-n-teal-11 animate-pulse"
            />
          </div>
          <div
            v-else-if="dialingCall && !activeCall"
            class="size-24 rounded-full bg-n-alpha-2 flex items-center justify-center mx-auto"
          >
            <span
              class="i-lucide-phone-outgoing size-10 text-n-slate-10 animate-pulse"
            />
          </div>
          <div
            v-else-if="activeCall"
            class="size-24 rounded-full bg-n-alpha-2 flex items-center justify-center mx-auto"
          >
            <span
              class="i-lucide-phone-call size-10 text-n-brand animate-pulse"
            />
          </div>
          <div
            v-else-if="inWrapup"
            class="size-24 rounded-full bg-n-amber-3 flex items-center justify-center mx-auto"
          >
            <span class="i-lucide-clock size-10 text-n-amber-11" />
          </div>
          <div
            v-else
            class="size-24 rounded-full flex items-center justify-center mx-auto"
            :style="{ backgroundColor: `${statusColor}1a` }"
          >
            <span
              class="i-lucide-pause-circle size-10"
              :style="{ color: statusColor }"
            />
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
            <p class="text-sm text-n-slate-11">
              <span v-if="activeCall" class="font-medium text-n-brand">
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
              class="text-xs text-n-amber-11 mt-1"
            >
              {{ dialerStatusMessage }}
            </p>
            <div v-if="!isAvailable && !activeCall" class="pt-3">
              <Button
                :label="t('JABVOX_DIALER.AVAILABLE')"
                icon="i-lucide-circle-check"
                variant="outline"
                color="teal"
                size="sm"
                @click="setDialerState(null)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>

    <!-- ── Campaign picker ── -->
    <template v-else>
      <div class="flex-1 overflow-y-auto">
        <div
          class="mx-auto w-full max-w-2xl flex flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8"
        >
          <!-- Header -->
          <div class="flex items-start gap-3">
            <span
              class="i-lucide-phone-call size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
            />
            <div class="min-w-0">
              <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
                {{ t('JABVOX_DIALER.TITLE') }}
              </h1>
              <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
                {{ t('JABVOX_DIALER.MY_CAMPAIGNS_HINT') }}
              </p>
            </div>
          </div>

          <!-- Loading -->
          <div
            v-if="uiFlags.isFetchingCampaigns"
            class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
          >
            <Spinner :size="18" />
            {{ t('JABVOX_PRODUCTS.LOADING') }}
          </div>

          <!-- Empty -->
          <EmptyStateLayout
            v-else-if="!myCampaigns.length"
            :title="t('JABVOX_DIALER.TITLE')"
            :subtitle="t('JABVOX_DIALER.NO_ASSIGNED_CAMPAIGNS')"
          />

          <!-- Campaign cards -->
          <div v-else class="flex flex-col gap-3">
            <div
              v-for="c in myCampaigns"
              :key="c.id"
              class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm flex items-center justify-between gap-4 transition-all hover:shadow-md"
            >
              <div class="flex items-center gap-3 min-w-0">
                <span
                  class="i-lucide-megaphone size-9 shrink-0 rounded-xl bg-n-alpha-1 p-2 text-n-slate-11"
                />
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-n-slate-12 truncate">
                    {{ c.name_jabvox }}
                  </p>
                  <p class="text-xs text-n-slate-10 mt-0.5">
                    {{ c.leads_count_jabvox }}
                    {{ t('JABVOX_DIALER.STATS.LEADS') }}
                  </p>
                </div>
              </div>
              <Button
                :label="t('JABVOX_DIALER.CONNECT')"
                icon="i-lucide-plug"
                size="sm"
                class="shrink-0"
                :is-loading="connecting"
                @click="onConnect(c)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
