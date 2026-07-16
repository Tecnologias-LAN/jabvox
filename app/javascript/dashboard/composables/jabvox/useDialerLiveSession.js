// Module-level singleton that holds the agent's LIVE dialer session (active call
// + wrap-up), independent of whether the Dialer page is mounted. This is what lets
// the call survive navigation: DialerPage writes its state here, and a global
// floating banner (mounted in Dashboard.vue) reads it so the agent can jump back
// to the dialer from anywhere without losing the call.
//
// Mirrors the pattern of useCallSession: the refs are created ONCE at module scope,
// so every importer shares the same reactive state.
import { ref, computed } from 'vue';

const SESSION_KEY = 'jabvox_dialer_session';

// Shared reactive state (singleton — declared at module scope on purpose).
const connected = ref(false);
const activeCampaign = ref(null);
const activeCall = ref(null);
const dialingCall = ref(null);
const inWrapup = ref(false);
const contactId = ref(null);

// True when there is something in progress the agent must not lose.
const hasLiveCall = computed(
  () =>
    connected.value &&
    Boolean(activeCall.value || dialingCall.value || inWrapup.value)
);

// Best-effort hydrate from sessionStorage (e.g. first mount after a full reload).
const hydrateFromStorage = () => {
  try {
    const raw = sessionStorage.getItem(SESSION_KEY);
    if (!raw) return;
    const s = JSON.parse(raw);
    connected.value = true;
    activeCampaign.value = s.campaign || null;
    activeCall.value = s.activeCall || null;
    dialingCall.value = s.dialingCall || null;
    inWrapup.value = Boolean(s.inWrapup);
    contactId.value =
      (s.activeCall || s.dialingCall || s.lastCall)?.contact_id ?? null;
  } catch {
    // ignore malformed storage
  }
};

// Called by DialerPage whenever its state changes, to mirror it globally.
const syncFromDialer = ({
  connected: conn,
  campaign,
  call,
  dialing,
  wrapup,
} = {}) => {
  connected.value = Boolean(conn);
  activeCampaign.value = campaign || null;
  activeCall.value = call || null;
  dialingCall.value = dialing || null;
  inWrapup.value = Boolean(wrapup);
  // Nullish coalescing: a contact_id of 0 is a valid id, not "missing".
  contactId.value = (call || dialing)?.contact_id ?? null;
};

const clear = () => {
  connected.value = false;
  activeCampaign.value = null;
  activeCall.value = null;
  dialingCall.value = null;
  inWrapup.value = false;
  contactId.value = null;
};

export function useDialerLiveSession() {
  return {
    connected,
    activeCampaign,
    activeCall,
    dialingCall,
    inWrapup,
    contactId,
    hasLiveCall,
    hydrateFromStorage,
    syncFromDialer,
    clear,
  };
}
