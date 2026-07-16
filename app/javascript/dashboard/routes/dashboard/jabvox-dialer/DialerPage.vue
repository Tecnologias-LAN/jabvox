<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
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
import leadsAPI from 'dashboard/api/jabvox/leads';
import messageAPI from 'dashboard/api/inbox/message';
import DialerWrapupForm from 'dashboard/routes/dashboard/jabvox-dialer/components/DialerWrapupForm.vue';
import { useDialerLiveSession } from 'dashboard/composables/jabvox/useDialerLiveSession';
import JabvoxLeadTableRows from 'dashboard/components/widgets/conversation/jabvox/JabvoxLeadTableRows.vue';
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

// Global singleton mirror of the live call, so it survives navigation and a
// floating banner can show it from any page.
const liveSession = useDialerLiveSession();

const campaigns = useMapGetter('jabvoxDialer/getCampaigns');
const dialerStates = useMapGetter('jabvoxDialer/getDialerStates');
const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');
const uiFlags = useMapGetter('jabvoxDialer/getUIFlags');
const currentUserId = useMapGetter('getCurrentUserID');
const multiTables = useMapGetter('jabvoxCustomization/getMultiTables');
const hasMultiTables = computed(() => (multiTables.value || []).length > 0);

const SESSION_KEY = 'jabvox_dialer_session';

// Decorative glyphs bound so they don't count as bare template strings.
const SECONDS_SUFFIX = 's';
const LEAD_PREFIX = '#';
const NOTE_SEPARATOR = '— ';
const MIDDOT = '·';

const canAccess = ref(true);
const checkingAccess = ref(true);
const connected = ref(false);
const activeCampaign = ref(null);
const connecting = ref(false);
const activeDialerState = ref(null); // null = available
const stateDropdownOpen = ref(false);
// Separate open-state for the dropdown shown inside the fullscreen call/wrap-up
// overlay, so it doesn't toggle together with the header one.
const overlayStateDropdownOpen = ref(false);
const activeCall = ref(null);
const dialingCall = ref(null); // call initiated, waiting for agent connection
const lastCall = ref(null); // persists call info during wrapup for gestión note
const dialerStatusMessage = ref(null);
const wrapupRemaining = ref(0);
const inWrapup = ref(false);
const wrapupNote = ref('');
const wrapupStateId = ref(null);
const wrapupGroup = ref(null);
const managementAnswers = ref({});
const isSavingNote = ref(false);
const typifications = ref([]);
const wrapupTypificationId = ref(null);

// The management picker (flat / two-level Estado→Subestado) now lives in
// DialerWrapupForm; the parent only needs the selected state for validation and
// content-attributes when saving the note.
const selectedManagementState = computed(() =>
  (managementStates.value || []).find(s => s.id === wrapupStateId.value)
);

// Changing the group invalidates a substate that belongs to another group.
watch(wrapupGroup, () => {
  const state = selectedManagementState.value;
  if (state && (state.state_group_jabvox || '') !== (wrapupGroup.value || ''))
    wrapupStateId.value = null;
});

// Person type label: 'persona' | 'empresa' → localized text (matches the lead
// detail view). Anything else falls back to the raw value.
const personTypeLabel = type => {
  if (type === 'empresa') return t('JABVOX_DIALER.CALL.PERSON_TYPE_COMPANY');
  if (type === 'persona') return t('JABVOX_DIALER.CALL.PERSON_TYPE_PERSON');
  return type || '';
};

// Default lead fields for the left column of the call workspace. Only shows the
// fields present on the payload (masked ones come as "***", hidden as blank).
const leadFields = computed(() => {
  const c = activeCall.value || lastCall.value || {};
  return [
    {
      label: t('JABVOX_DIALER.CALL.F_PHONE'),
      value: c.contact_phone,
      icon: 'i-lucide-phone',
    },
    {
      label: t('JABVOX_DIALER.CALL.F_EMAIL'),
      value: c.contact_email,
      icon: 'i-lucide-mail',
    },
    {
      label: t('JABVOX_DIALER.CALL.F_DOCUMENT'),
      value: c.contact_document,
      icon: 'i-lucide-id-card',
    },
    {
      label: t('JABVOX_DIALER.CALL.F_PERSON_TYPE'),
      value: personTypeLabel(c.contact_type),
      icon: 'i-lucide-user',
    },
    {
      label: t('JABVOX_DIALER.CALL.F_COUNTRY'),
      value: c.contact_country,
      icon: 'i-lucide-globe',
    },
    {
      label: t('JABVOX_DIALER.CALL.F_AFFILIATE'),
      value: c.affiliate_name,
      icon: 'i-lucide-users',
    },
    {
      label: t('JABVOX_DIALER.CALL.F_CAMPAIGN'),
      value: c.campaign_name,
      icon: 'i-lucide-tag',
    },
    {
      label: t('JABVOX_DIALER.CALL.F_LEAD_NUMBER'),
      value: c.lead_number,
      icon: 'i-lucide-hash',
    },
  ].filter(
    f => f.value !== undefined && f.value !== null && `${f.value}`.trim() !== ''
  );
});

// Account-specific custom lead fields (Sección, zona, etc.), loaded per call.
// [{ label, value }] with the account's labels; every defined column is shown so
// the agent sees the full lead sheet (empty ones as "—"), like the lead detail.
const leadCustomFields = ref([]);
const loadingLeadFields = ref(false);
const NO_VALUE = '—';

const loadLeadCustomFields = async contactId => {
  leadCustomFields.value = [];
  if (!contactId) return;
  loadingLeadFields.value = true;
  try {
    const { data } = await leadsAPI.forContact(contactId);
    const defs = data.custom_field_defs || [];
    const values = data.fields || {};
    leadCustomFields.value = defs.map(d => ({
      label: d.label || d.key,
      value: values[`custom:${d.key}`] || '',
    }));
  } catch {
    leadCustomFields.value = [];
  } finally {
    loadingLeadFields.value = false;
  }
};
let heartbeatTimer = null;
let requestCallTimer = null;
let wrapupTimer = null;

const clearWrapupTimer = () => {
  if (wrapupTimer) {
    clearInterval(wrapupTimer);
    wrapupTimer = null;
  }
};

// Persist the FULL dialer state (campaign + live call / wrap-up) so navigating
// away to a conversation and back does not drop the call. wrapupEndsAt is an
// absolute epoch (ms) so the countdown can be recomputed after remount instead
// of restarting from the full wrap-up time.
const persistState = () => {
  if (!connected.value || !activeCampaign.value) {
    // Disconnected: clear the global live session too so the banner disappears.
    liveSession.syncFromDialer({ connected: false });
    return;
  }
  try {
    const wrapupEndsAt =
      inWrapup.value && wrapupRemaining.value > 0
        ? Date.now() + wrapupRemaining.value * 1000
        : null;
    sessionStorage.setItem(
      SESSION_KEY,
      JSON.stringify({
        campaign: activeCampaign.value,
        dialerStateId: activeDialerState.value?.id ?? null,
        activeCall: activeCall.value,
        dialingCall: dialingCall.value,
        lastCall: lastCall.value,
        inWrapup: inWrapup.value,
        wrapupEndsAt,
      })
    );
  } catch {
    // ignore storage errors
  }
  // Mirror into the global singleton so the floating banner reflects the call
  // from any page (survives navigation away from the dialer).
  liveSession.syncFromDialer({
    connected: connected.value,
    campaign: activeCampaign.value,
    call: activeCall.value,
    dialing: dialingCall.value,
    wrapup: inWrapup.value,
  });
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

// "(08:00–18:00 · 2026-07-01 → 2026-07-15)" for the out-of-schedule note.
const scheduleLabel = c => {
  const parts = [];
  if (c.calling_hours_start_jabvox && c.calling_hours_end_jabvox) {
    parts.push(`${c.calling_hours_start_jabvox}–${c.calling_hours_end_jabvox}`);
  }
  if (c.schedule_start_date_jabvox || c.schedule_end_date_jabvox) {
    parts.push(
      `${c.schedule_start_date_jabvox || ''} → ${c.schedule_end_date_jabvox || ''}`.trim()
    );
  }
  return parts.length ? `(${parts.join(' · ')})` : '';
};

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
  // Load the account's custom lead fields for the left column of the call screen.
  loadLeadCustomFields(data.contact_id);
  persistState();
};

const endWrapup = () => {
  clearWrapupTimer();
  inWrapup.value = false;
  wrapupRemaining.value = 0;
  lastCall.value = null;
  wrapupNote.value = '';
  wrapupStateId.value = null;
  wrapupGroup.value = null;
  wrapupTypificationId.value = null;
  managementAnswers.value = {};
  persistState();
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
  persistState();
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
    overlayStateDropdownOpen.value = false;
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
    store.dispatch('jabvoxCustomization/fetchTables').catch(() => {}),
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

      // Restore an in-progress call / wrap-up so navigating to a conversation
      // and back does NOT drop the call or its typification step.
      activeCall.value = session.activeCall || null;
      dialingCall.value = session.dialingCall || null;
      lastCall.value = session.lastCall || null;

      // Re-load the lead's custom fields after navigating back into the dialer.
      const restoredContactId = (activeCall.value || lastCall.value)
        ?.contact_id;
      if (restoredContactId) loadLeadCustomFields(restoredContactId);

      if (session.inWrapup) {
        // Resume the wrap-up countdown from where it left off.
        const remainingMs = (session.wrapupEndsAt || 0) - Date.now();
        if (remainingMs > 0) {
          inWrapup.value = true;
          wrapupRemaining.value = Math.ceil(remainingMs / 1000);
          clearWrapupTimer();
          wrapupTimer = setInterval(() => {
            wrapupRemaining.value -= 1;
            if (wrapupRemaining.value <= 0) saveWrapupNote().then(endWrapup);
          }, 1000);
        } else {
          // Wrap-up window already elapsed while away — save + finish it.
          inWrapup.value = true;
          saveWrapupNote().then(endWrapup);
        }
      }

      // Only resume polling for new calls when the agent is idle and available.
      if (
        !activeCall.value &&
        !dialingCall.value &&
        !inWrapup.value &&
        activeDialerState.value === null
      ) {
        startRequestCallPolling();
      }
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
  // IMPORTANT: do NOT disconnect the agent here. This unmount fires whenever the
  // user navigates away (e.g. "ir a conversación" during a call). Disconnecting
  // would drop the agent from the Asterisk queue and lose the live call. The
  // session is persisted (persistState) and restored on remount; the real
  // disconnect only happens via the explicit "Desconectar" button (onDisconnect)
  // or when the heartbeat expires server-side.
  persistState();
});

const onConnect = async campaign => {
  connecting.value = true;
  try {
    await dialerAccessesAPI.connect(campaign.id);
    activeCampaign.value = campaign;
    activeDialerState.value = null;
    connected.value = true;
    persistState();
    startHeartbeat();
    startRequestCallPolling();
  } catch {
    // connect failed — stay disconnected
  } finally {
    connecting.value = false;
  }
};

const onDisconnect = async () => {
  // If disconnecting mid-call, hang up the live call first so it doesn't stay
  // ringing on the phone after the agent leaves the queue.
  const liveContactId =
    activeCall.value?.dialer_contact_id || dialingCall.value?.dialer_contact_id;
  if (liveContactId) {
    await dialerAccessesAPI.endCall(liveContactId).catch(() => {});
  }
  stopHeartbeat();
  stopRequestCallPolling();
  clearWrapupTimer();
  clearSession();
  liveSession.clear();
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
  wrapupGroup.value = null;
  managementAnswers.value = {};
  stateDropdownOpen.value = false;
  overlayStateDropdownOpen.value = false;
};

const setDialerState = async state => {
  activeDialerState.value = state;
  stateDropdownOpen.value = false;
  overlayStateDropdownOpen.value = false;
  dialerAccessesAPI.updateState(state?.id ?? null).catch(() => {});
  persistState();
  if (state === null) {
    startRequestCallPolling();
  } else {
    stopRequestCallPolling();
  }
};
</script>

<template>
  <div
    class="relative flex flex-col h-full w-full overflow-hidden bg-n-background"
  >
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
      <!-- Dialing card (call initiated, waiting for agent connection) -->
      <div
        v-if="dialingCall && !activeCall && !inWrapup"
        class="shrink-0 w-full max-w-3xl mx-auto px-4 sm:px-6"
      >
        <div
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
      </div>

      <!-- ════ Fullscreen call / wrap-up workspace ════
           Left: lead default + custom fields. Right: full typification. -->
      <div
        v-if="activeCall || inWrapup"
        class="absolute inset-0 z-40 flex flex-col bg-n-background"
      >
        <!-- Top bar: status + contact + primary actions -->
        <div
          class="shrink-0 flex items-center justify-between gap-4 px-5 sm:px-8 py-4 border-b"
          :class="
            activeCall
              ? 'border-n-brand/30 bg-n-alpha-2'
              : 'border-n-amber-6 bg-n-amber-3'
          "
        >
          <div class="flex items-center gap-3 min-w-0">
            <span
              v-if="activeCall"
              class="i-lucide-phone-call size-7 text-n-brand shrink-0 animate-pulse"
            />
            <span
              v-else
              class="i-lucide-clock size-7 text-n-amber-11 shrink-0"
            />
            <div class="min-w-0">
              <p
                class="text-lg font-bold text-n-slate-12 leading-tight truncate"
              >
                {{
                  (activeCall || lastCall)?.contact_name ||
                  (activeCall || lastCall)?.contact_phone
                }}
                <span
                  v-if="(activeCall || lastCall)?.lead_number"
                  class="ml-2 text-sm font-normal text-n-slate-10"
                  >{{ LEAD_PREFIX
                  }}{{ (activeCall || lastCall).lead_number }}</span
                >
              </p>
              <p
                class="text-sm leading-tight truncate"
                :class="activeCall ? 'text-n-brand' : 'text-n-amber-11'"
              >
                <template v-if="activeCall">
                  {{ t('JABVOX_DIALER.CALL.IN_CALL') }}
                </template>
                <template v-else>
                  {{ t('JABVOX_DIALER.WRAPUP.TITLE') }} {{ MIDDOT }}
                  <span class="font-bold tabular-nums"
                    >{{ wrapupRemaining }}{{ SECONDS_SUFFIX }}</span
                  >
                </template>
              </p>
            </div>
          </div>

          <div class="shrink-0 flex items-center gap-2">
            <!-- State selector + disconnect, also available during call/wrap-up -->
            <div class="relative" data-state-dropdown>
              <button
                class="flex items-center gap-1.5 text-sm font-medium px-3 py-2 rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
                @click.stop="
                  overlayStateDropdownOpen = !overlayStateDropdownOpen
                "
              >
                <span
                  class="size-2 rounded-full shrink-0"
                  :style="{ backgroundColor: statusColor }"
                />
                {{ statusLabel }}
                <span class="i-lucide-chevron-down size-3.5" />
              </button>

              <div
                v-if="overlayStateDropdownOpen"
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

            <Button
              v-if="activeCall"
              :label="t('JABVOX_DIALER.CALL.END')"
              icon="i-lucide-phone-off"
              color="ruby"
              @click="onEndCall"
            />
            <Button
              v-if="activeCall && activeCall.conversation_id"
              :label="t('JABVOX_DIALER.CALL.OPEN_CONVERSATION')"
              icon="i-lucide-external-link"
              variant="outline"
              color="slate"
              @click="openConversation"
            />
            <Button
              v-if="inWrapup && !activeCall"
              :label="t('JABVOX_DIALER.WRAPUP.NEXT')"
              icon="i-lucide-skip-forward"
              color="amber"
              :is-loading="isSavingNote"
              @click="saveWrapupNote().then(endWrapup)"
            />
          </div>
        </div>

        <!-- Wrap-up progress bar -->
        <div
          v-if="inWrapup && !activeCall"
          class="shrink-0 h-1 w-full bg-n-amber-6 overflow-hidden"
        >
          <div
            class="h-full bg-n-amber-9 transition-all duration-1000 ease-linear"
            :style="{
              width: `${(wrapupRemaining / (activeCampaign?.wrapup_time_jabvox || 30)) * 100}%`,
            }"
          />
        </div>

        <!-- Two-column body -->
        <div class="flex-1 min-h-0 flex flex-col lg:flex-row overflow-hidden">
          <!-- ── LEFT: lead default + custom fields ── -->
          <div
            class="lg:w-1/2 lg:border-r border-n-weak overflow-y-auto p-5 sm:p-8 space-y-6"
          >
            <div>
              <h3
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-3"
              >
                {{ t('JABVOX_DIALER.CALL.LEAD_INFO') }}
              </h3>
              <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
                <div v-for="f in leadFields" :key="f.label" class="min-w-0">
                  <dt
                    class="text-[11px] font-medium uppercase text-n-slate-9 flex items-center gap-1"
                  >
                    <span class="size-3 shrink-0" :class="[f.icon]" />
                    {{ f.label }}
                  </dt>
                  <dd class="text-sm text-n-slate-12 truncate mt-0.5">
                    {{ f.value }}
                  </dd>
                </div>
              </dl>
            </div>

            <!-- Account-specific custom lead fields (Sección, zona, alias…) -->
            <div
              v-if="loadingLeadFields || leadCustomFields.length"
              class="pt-4 border-t border-n-weak"
            >
              <h3
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-3"
              >
                {{ t('JABVOX_DIALER.CALL.LEAD_CUSTOM_FIELDS') }}
              </h3>
              <div
                v-if="loadingLeadFields"
                class="text-sm text-n-slate-10 flex items-center gap-2"
              >
                <Spinner class="size-4" />
                {{ t('JABVOX_DIALER.CALL.LOADING_FIELDS') }}
              </div>
              <dl
                v-else
                class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3"
              >
                <div
                  v-for="f in leadCustomFields"
                  :key="f.label"
                  class="min-w-0"
                >
                  <dt class="text-[11px] font-medium uppercase text-n-slate-9">
                    {{ f.label }}
                  </dt>
                  <dd class="text-sm text-n-slate-12 truncate mt-0.5">
                    {{ `${f.value}`.trim() || NO_VALUE }}
                  </dd>
                </div>
              </dl>
            </div>

            <!-- Multi-row custom tables (Asesorías, Casos…) -->
            <div
              v-if="(activeCall || lastCall)?.lead_id && hasMultiTables"
              class="pt-4 border-t border-n-weak"
            >
              <h3
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-3"
              >
                {{ t('JABVOX_DIALER.CALL.CUSTOM_TABLES') }}
              </h3>
              <JabvoxLeadTableRows
                :lead-id="(activeCall || lastCall).lead_id"
              />
            </div>

            <!-- Gestión history -->
            <div
              v-if="(activeCall || lastCall)?.management_history?.length"
              class="pt-4 border-t border-n-weak"
            >
              <h3
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-3"
              >
                {{ t('JABVOX_DIALER.HISTORY.TITLE') }}
              </h3>
              <div class="space-y-1.5">
                <div
                  v-for="(g, i) in (activeCall || lastCall).management_history"
                  :key="i"
                  class="flex items-start gap-2"
                >
                  <span
                    class="inline-block size-2.5 rounded-full shrink-0 mt-1"
                    :style="{ backgroundColor: g.state_color || '#6b7280' }"
                  />
                  <div class="min-w-0 text-sm leading-tight">
                    <span class="font-medium text-n-slate-11">{{
                      g.state_name
                    }}</span>
                    <span v-if="g.note" class="text-n-slate-10 ml-1">
                      {{ NOTE_SEPARATOR }}{{ g.note }}
                    </span>
                    <span class="text-n-slate-9 ml-1 text-xs">{{
                      g.created_at
                    }}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- ── RIGHT: full typification ── -->
          <div class="lg:w-1/2 overflow-y-auto p-5 sm:p-8 bg-n-solid-1/40">
            <h3
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-4"
            >
              {{ t('JABVOX_DIALER.CALL.TYPIFICATION') }}
            </h3>
            <DialerWrapupForm
              v-model:state-id="wrapupStateId"
              v-model:group="wrapupGroup"
              v-model:answers="managementAnswers"
              v-model:typification-id="wrapupTypificationId"
              v-model:note="wrapupNote"
              :management-states="managementStates || []"
              :typifications="typifications"
              :has-conversation="
                Boolean((activeCall || lastCall)?.conversation_id)
              "
            />
            <div v-if="inWrapup && !activeCall" class="mt-5">
              <Button
                :label="t('JABVOX_DIALER.WRAPUP.SAVE_NEXT')"
                icon="i-lucide-check"
                color="amber"
                class="w-full justify-center"
                :is-loading="isSavingNote"
                @click="saveWrapupNote().then(endWrapup)"
              />
            </div>
          </div>
        </div>
      </div>
      <!-- /Fullscreen call/wrapup workspace -->

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
              class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm flex items-center justify-between gap-4 transition-all"
              :class="
                c.in_schedule === false ? 'opacity-60' : 'hover:shadow-md'
              "
            >
              <div class="flex items-center gap-3 min-w-0">
                <span
                  class="size-9 shrink-0 rounded-xl bg-n-alpha-1 p-2"
                  :class="
                    c.in_schedule === false
                      ? 'i-lucide-clock-alert text-n-amber-11'
                      : 'i-lucide-megaphone text-n-slate-11'
                  "
                />
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-n-slate-12 truncate">
                    {{ c.name_jabvox }}
                  </p>
                  <p class="text-xs text-n-slate-10 mt-0.5">
                    {{ c.leads_count_jabvox }}
                    {{ t('JABVOX_DIALER.STATS.LEADS') }}
                  </p>
                  <p
                    v-if="c.in_schedule === false"
                    class="text-xs text-n-amber-11 mt-0.5"
                  >
                    {{ t('JABVOX_DIALER.OUT_OF_SCHEDULE') }}
                    {{ scheduleLabel(c) }}
                  </p>
                </div>
              </div>
              <Button
                :label="
                  c.in_schedule === false
                    ? t('JABVOX_DIALER.OUT_OF_SCHEDULE_SHORT')
                    : t('JABVOX_DIALER.CONNECT')
                "
                icon="i-lucide-plug"
                size="sm"
                class="shrink-0"
                :is-loading="connecting"
                :disabled="c.in_schedule === false"
                @click="onConnect(c)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
