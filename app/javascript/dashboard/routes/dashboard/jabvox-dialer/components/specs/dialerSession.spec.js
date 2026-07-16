// Pure-logic tests for the dialer session persistence that keeps a live call
// alive across navigation (go to conversation and back). Mirrors the persist /
// restore logic in DialerPage.vue without mounting the full component.

const SESSION_KEY = 'jabvox_dialer_session';

// --- Replicated persist/restore (must stay in sync with DialerPage.vue) ---
const persist = (state, now) => {
  if (!state.connected || !state.activeCampaign) return;
  const wrapupEndsAt =
    state.inWrapup && state.wrapupRemaining > 0
      ? now + state.wrapupRemaining * 1000
      : null;
  sessionStorage.setItem(
    SESSION_KEY,
    JSON.stringify({
      campaign: state.activeCampaign,
      dialerStateId: state.activeDialerState?.id ?? null,
      activeCall: state.activeCall,
      dialingCall: state.dialingCall,
      lastCall: state.lastCall,
      inWrapup: state.inWrapup,
      wrapupEndsAt,
    })
  );
};

const restore = now => {
  const raw = sessionStorage.getItem(SESSION_KEY);
  if (!raw) return null;
  const s = JSON.parse(raw);
  const out = {
    connected: true,
    activeCampaign: s.campaign,
    activeCall: s.activeCall || null,
    dialingCall: s.dialingCall || null,
    lastCall: s.lastCall || null,
    inWrapup: false,
    wrapupRemaining: 0,
  };
  if (s.inWrapup) {
    const remainingMs = (s.wrapupEndsAt || 0) - now;
    if (remainingMs > 0) {
      out.inWrapup = true;
      out.wrapupRemaining = Math.ceil(remainingMs / 1000);
    } else {
      out.inWrapup = true; // window elapsed → save+finish path
      out.wrapupRemaining = 0;
    }
  }
  return out;
};

const baseCall = {
  dialer_contact_id: 42,
  contact_name: 'Lead X',
  contact_phone: '573000000001',
  conversation_id: 99,
};

describe('dialer session persistence (navigation keeps the call)', () => {
  beforeEach(() => sessionStorage.clear());

  it('persists and restores an active call unchanged', () => {
    persist(
      {
        connected: true,
        activeCampaign: { id: 7, name_jabvox: 'C' },
        activeCall: baseCall,
        dialingCall: null,
        lastCall: null,
        inWrapup: false,
        wrapupRemaining: 0,
      },
      1_000_000
    );
    const r = restore(1_000_500);
    expect(r.activeCall).toEqual(baseCall);
    expect(r.connected).toBe(true);
    expect(r.inWrapup).toBe(false);
  });

  it('recomputes wrap-up countdown from the absolute end time', () => {
    persist(
      {
        connected: true,
        activeCampaign: { id: 7 },
        activeCall: null,
        dialingCall: null,
        lastCall: baseCall,
        inWrapup: true,
        wrapupRemaining: 30,
      },
      1_000_000 // persisted at t=1_000_000 → ends at 1_030_000
    );
    // Restored 12s later → ~18s remaining.
    const r = restore(1_012_000);
    expect(r.inWrapup).toBe(true);
    expect(r.wrapupRemaining).toBe(18);
    expect(r.lastCall).toEqual(baseCall);
  });

  it('finishes wrap-up when the window already elapsed while away', () => {
    persist(
      {
        connected: true,
        activeCampaign: { id: 7 },
        activeCall: null,
        dialingCall: null,
        lastCall: baseCall,
        inWrapup: true,
        wrapupRemaining: 30,
      },
      1_000_000 // ends at 1_030_000
    );
    const r = restore(1_100_000); // 70s past the end
    expect(r.inWrapup).toBe(true);
    expect(r.wrapupRemaining).toBe(0);
  });

  it('does not persist when not connected (no phantom sessions)', () => {
    persist(
      { connected: false, activeCampaign: { id: 7 }, activeCall: baseCall },
      1_000_000
    );
    expect(sessionStorage.getItem(SESSION_KEY)).toBeNull();
  });

  it('STRESS: 500 navigate-away/back cycles never lose or corrupt the call', () => {
    let now = 1_000_000;
    let state = {
      connected: true,
      activeCampaign: { id: 7, name_jabvox: 'Camp' },
      activeCall: baseCall,
      dialingCall: null,
      lastCall: null,
      inWrapup: false,
      wrapupRemaining: 0,
    };
    for (let i = 0; i < 500; i += 1) {
      persist(state, now); // unmount (navigate away)
      now += 1500; // ~1.5s away
      const restored = restore(now); // remount (navigate back)
      expect(restored).not.toBeNull();
      expect(restored.activeCall.dialer_contact_id).toBe(42);
      expect(restored.activeCall.conversation_id).toBe(99);
      state = { ...state, ...restored };
    }
    // After 500 cycles the call is still intact.
    expect(state.activeCall.contact_phone).toBe('573000000001');
  });

  it('STRESS: rapid wrap-up cycles keep the countdown monotonic and bounded', () => {
    let now = 2_000_000;
    let state = {
      connected: true,
      activeCampaign: { id: 7 },
      activeCall: null,
      dialingCall: null,
      lastCall: baseCall,
      inWrapup: true,
      wrapupRemaining: 30,
    };
    let prev = 31;
    for (let i = 0; i < 60; i += 1) {
      persist(state, now);
      now += 1000; // 1s per tick
      const r = restore(now);
      // remaining must never grow and never exceed the original window
      expect(r.wrapupRemaining).toBeLessThanOrEqual(prev);
      expect(r.wrapupRemaining).toBeLessThanOrEqual(30);
      expect(r.wrapupRemaining).toBeGreaterThanOrEqual(0);
      prev = r.wrapupRemaining;
      state = { ...state, ...r };
      if (r.wrapupRemaining === 0) break;
    }
    expect(prev).toBe(0);
  });
});
