import { useDialerLiveSession } from '../useDialerLiveSession';

// The composable is a module-level singleton, so every call shares state.
describe('useDialerLiveSession (global dialer call singleton)', () => {
  beforeEach(() => {
    sessionStorage.clear();
    useDialerLiveSession().clear();
  });

  it('starts with no live call', () => {
    const s = useDialerLiveSession();
    expect(s.hasLiveCall.value).toBe(false);
  });

  it('reflects an active call synced from the dialer', () => {
    const s = useDialerLiveSession();
    s.syncFromDialer({
      connected: true,
      campaign: { id: 3, name_jabvox: 'C' },
      call: { contact_id: 7, contact_name: 'Ana', conversation_id: 12 },
    });
    expect(s.hasLiveCall.value).toBe(true);
    expect(s.activeCall.value.contact_name).toBe('Ana');
    expect(s.contactId.value).toBe(7);
  });

  it('shares state across separate calls (singleton)', () => {
    useDialerLiveSession().syncFromDialer({
      connected: true,
      campaign: { id: 1 },
      dialing: { contact_id: 9 },
    });
    // A different importer sees the same state.
    const other = useDialerLiveSession();
    expect(other.hasLiveCall.value).toBe(true);
    expect(other.dialingCall.value.contact_id).toBe(9);
  });

  it('is not "live" when disconnected even with a stale call object', () => {
    const s = useDialerLiveSession();
    s.syncFromDialer({ connected: false, call: { contact_id: 1 } });
    expect(s.hasLiveCall.value).toBe(false);
  });

  it('counts wrap-up as a live session', () => {
    const s = useDialerLiveSession();
    s.syncFromDialer({ connected: true, campaign: { id: 1 }, wrapup: true });
    expect(s.hasLiveCall.value).toBe(true);
  });

  it('clear() ends the live session', () => {
    const s = useDialerLiveSession();
    s.syncFromDialer({ connected: true, call: { contact_id: 1 } });
    s.clear();
    expect(s.hasLiveCall.value).toBe(false);
    expect(s.activeCall.value).toBeNull();
  });

  it('hydrateFromStorage rebuilds the session after a reload', () => {
    sessionStorage.setItem(
      'jabvox_dialer_session',
      JSON.stringify({
        campaign: { id: 5 },
        activeCall: { contact_id: 42, contact_name: 'Beto' },
        inWrapup: false,
      })
    );
    const s = useDialerLiveSession();
    s.hydrateFromStorage();
    expect(s.hasLiveCall.value).toBe(true);
    expect(s.activeCall.value.contact_name).toBe('Beto');
    expect(s.contactId.value).toBe(42);
  });

  it('STRESS: 1000 rapid sync/clear cycles stay consistent', () => {
    const s = useDialerLiveSession();
    for (let i = 0; i < 1000; i += 1) {
      s.syncFromDialer({
        connected: true,
        campaign: { id: 1 },
        call: { contact_id: i },
      });
      expect(s.hasLiveCall.value).toBe(true);
      expect(s.contactId.value).toBe(i);
    }
    s.clear();
    expect(s.hasLiveCall.value).toBe(false);
  });
});
