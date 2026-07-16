import { ref, onMounted, onUnmounted } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { useAlert } from 'dashboard/composables';
import { clickToCallAPI } from 'dashboard/api/jabvox/clickToCall';

// Shared singleton state so the call overlay is global (one active call at a time).
const phase = ref(null); // null | 'calling' | 'typify'
const callLogId = ref(null);
const uniqueid = ref(null);
const target = ref({ name: '', phone: '' });

/**
 * Drives the click-to-call flow: HTTP originate → wait for the `jabvox.call.ended`
 * WebSocket event (or manual hangup) → typify dialog.
 */
export function useClickToCall() {
  const initiateCall = async ({
    contactId,
    leadId,
    conversationId,
    name,
    phone,
  }) => {
    target.value = { name: name || '', phone: phone || '' };
    try {
      const payload = {};
      if (leadId) payload.lead_id = leadId;
      else if (contactId) payload.contact_id = contactId;
      else if (conversationId) payload.conversation_id = conversationId;

      const { data } = await clickToCallAPI.initiate(payload);
      callLogId.value = data.call_log_id;
      uniqueid.value = null;
      phase.value = 'calling';
    } catch (error) {
      useAlert(error?.response?.data?.error || 'No se pudo iniciar la llamada');
    }
  };

  const hangup = async () => {
    if (callLogId.value) {
      try {
        await clickToCallAPI.hangup(callLogId.value);
      } catch (error) {
        // ignore — Asterisk may have already torn down the channel
      }
    }
    phase.value = 'typify';
  };

  const close = () => {
    phase.value = null;
    callLogId.value = null;
    uniqueid.value = null;
    target.value = { name: '', phone: '' };
  };

  const submitTypification = async ({ typificationId, note, management }) => {
    try {
      // uniqueid is captured server-side (at originate + on hangup); the client never
      // sends it, so a missing hangup event can't blank the CDR link.
      await clickToCallAPI.typify(callLogId.value, {
        typification_id: typificationId,
        note,
        management,
      });
      close();
    } catch (error) {
      useAlert('No se pudo guardar la tipificación');
    }
  };

  return {
    phase,
    callLogId,
    uniqueid,
    target,
    initiateCall,
    hangup,
    submitTypification,
    close,
  };
}

// Wires the WebSocket event once (used by the global overlay host).
export function useClickToCallListener() {
  const onCallEnded = data => {
    const incoming = data?.call_log_id;
    // Match by value, tolerant of type (the id is a Number from the originate
    // HTTP response but may arrive as a String over the WebSocket). Also open
    // typify when there's an active call whose local id was lost — the overlay
    // is single-call, so an unmatched call.ended still means "this call ended".
    const matches =
      incoming != null &&
      callLogId.value != null &&
      String(incoming) === String(callLogId.value);
    const activeButUnmatched =
      phase.value === 'calling' && callLogId.value == null;

    if (matches || activeButUnmatched) {
      uniqueid.value = data.uniqueid;
      if (callLogId.value == null && incoming != null)
        callLogId.value = incoming;
      phase.value = 'typify';
    }
  };

  onMounted(() => emitter.on('jabvox.call.ended', onCallEnded));
  onUnmounted(() => emitter.off('jabvox.call.ended', onCallEnded));
}
