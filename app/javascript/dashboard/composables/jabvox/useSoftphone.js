import { ref, computed } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import store from 'dashboard/store';
import SoftphoneAPI from 'dashboard/api/jabvox/softphone';
import SipClient from 'dashboard/routes/dashboard/jabvox-softphone/services/SipClient';

// Estado singleton: una sola instancia del softphone en toda la app (una llamada a la vez).
/** @type {import('vue').Ref<'disconnected'|'registering'|'registered'|'calling'|'in_call'|'failed'>} */
const state = ref('disconnected');
const dialedNumber = ref('');
const isOpen = ref(false);
const isMinimized = ref(false);
const isMuted = ref(false);
const lastError = ref(null);
const currentTarget = ref({ name: '', phone: '' });
// Extensión y datos de conexión de las credenciales actuales (se muestran en la cabecera).
const extension = ref('');
// Historial de llamadas (se carga bajo demanda al abrir la pestaña).
const callLogs = ref([]);
// Id del log de la llamada en curso (para cerrarlo al terminar).
let activeCallLogId = null;
// Cuenta con la que el softphone está registrado actualmente. Un usuario puede estar en
// varias cuentas con extensiones distintas: siempre debe llamar con la ext de la cuenta
// en la que está. Si cambia de cuenta, re-registramos con la nueva extensión.
const connectedAccountId = ref(null);

/** @type {SipClient|null} */
let sip = null;
/** @type {HTMLAudioElement|null} */
let remoteAudio = null;
// Promesa del registro en curso: evita lanzar dos registros a la vez (pre-conexión
// al abrir + clic en Llamar). Todos los llamadores esperan el MISMO registro, así el
// primer clic ya saca la llamada sin tener que reintentar.
let connectPromise = null;
// Intervalo del heartbeat de presencia (reporta el estado en vivo al backend).
let presenceTimer = null;
const PRESENCE_INTERVAL_MS = 20000;

/**
 * Softphone WebRTC (SIP.js). Gestiona registro, llamadas manuales/click-to-call/dialer,
 * DTMF y transferencia. Emite eventos globales (jabvox.softphone.*) para analíticas y
 * webhooks sin bloquear la llamada.
 */
export function useSoftphone() {
  const isRegistered = computed(() =>
    ['registered', 'calling', 'in_call'].includes(state.value)
  );
  const isInCall = computed(() => ['calling', 'in_call'].includes(state.value));

  /** Asegura un <audio> oculto para el audio remoto. */
  const ensureRemoteAudio = () => {
    if (remoteAudio) return remoteAudio;
    remoteAudio = document.createElement('audio');
    remoteAudio.setAttribute('autoplay', 'true');
    remoteAudio.style.display = 'none';
    document.body.appendChild(remoteAudio);
    return remoteAudio;
  };

  /** Id de la cuenta activa (la de la URL/sesión actual). */
  const currentAccountId = () => store.getters.getCurrentAccountId;

  // === Presencia (heartbeat para el panel del super admin) ===

  /**
   * Reporta el estado en vivo de la extensión al backend. Nunca rompe el softphone:
   * un fallo de red aquí es irrelevante para la llamada.
   */
  const reportPresence = async () => {
    try {
      await SoftphoneAPI.reportPresence({
        state: state.value,
        error: lastError.value || null,
        user_agent_info:
          typeof navigator !== 'undefined' ? navigator.userAgent : null,
      });
    } catch (e) {
      /* presencia informativa: se ignora el error */
    }
  };

  /** Arranca el heartbeat periódico (idempotente). */
  const startPresenceHeartbeat = () => {
    if (presenceTimer) return;
    reportPresence();
    presenceTimer = setInterval(reportPresence, PRESENCE_INTERVAL_MS);
  };

  /** Detiene el heartbeat y marca desconectado una última vez. */
  const stopPresenceHeartbeat = () => {
    if (presenceTimer) {
      clearInterval(presenceTimer);
      presenceTimer = null;
    }
  };

  // === Historial ===

  /** Carga el historial del usuario (para la pestaña de historial). */
  const loadCallLogs = async () => {
    try {
      const { data } = await SoftphoneAPI.getCallLogs();
      callLogs.value = data;
    } catch (error) {
      // el historial es informativo; un fallo no debe romper el softphone
      callLogs.value = [];
    }
  };

  /** Registra el inicio de una llamada saliente. */
  const openCallLog = async target => {
    try {
      const { data } = await SoftphoneAPI.createCallLog({
        phone_number: target,
        extension: extension.value,
        contact_name: currentTarget.value.name || null,
        direction: 'outbound',
      });
      activeCallLogId = data.id;
    } catch (error) {
      activeCallLogId = null;
    }
  };

  /** Marca la llamada como contestada y guarda el codec negociado. @param {string} codec */
  const markCallAnswered = async codec => {
    if (!activeCallLogId) return;
    try {
      await SoftphoneAPI.updateCallLog(activeCallLogId, {
        answered_at: new Date().toISOString(),
        status: 'answered',
        codec: codec || null,
      });
    } catch (error) {
      /* no crítico: el logging nunca rompe la llamada */
    }
  };

  /**
   * Cierra la llamada activa en el historial, con motivo de fallo si aplica.
   * @param {string} status
   * @param {{reason?: string, code?: string, endedBy?: string}} [failure]
   */
  const closeCallLog = async (status, failure = {}) => {
    if (!activeCallLogId) return;
    const id = activeCallLogId;
    activeCallLogId = null;
    try {
      await SoftphoneAPI.updateCallLog(id, {
        finish: true,
        status,
        failure_reason: failure.reason || null,
        failure_code: failure.code || null,
        ended_by: failure.endedBy || null,
      });
    } catch (error) {
      /* no crítico */
    }
  };

  /**
   * Obtiene credenciales del backend y registra la extensión de la CUENTA ACTUAL.
   * Si ya está registrado con la misma cuenta, no hace nada. Si el usuario cambió a otra
   * cuenta (donde puede tener otra extensión), desconecta y re-registra con la nueva.
   * @returns {Promise<boolean>}
   */
  const doConnect = async accountId => {
    // Cuenta distinta a la registrada: soltar la conexión previa antes de re-registrar.
    if (sip && connectedAccountId.value !== accountId) {
      await sip.disconnect();
      sip = null;
    }

    try {
      // getCredentials es accountScoped: la URL lleva la cuenta actual, así que el backend
      // devuelve la extensión del usuario EN ESA cuenta.
      const { data } = await SoftphoneAPI.getCredentials();
      // El backend responde snake_case; SipClient espera camelCase.
      const creds = {
        wssUrl: data.wss_url,
        sipDomain: data.sip_domain,
        sipUri: data.sip_uri,
        authUser: data.auth_user,
        sipPassword: data.sip_password,
        codecs: data.codecs,
        dtmfMode: data.dtmf_mode,
        autoAnswer: data.auto_answer,
        transferEnabled: data.transfer_enabled,
        iceServers: data.ice_servers,
        ttl: data.ttl,
      };
      extension.value = data.extension || '';
      sip = new SipClient(creds, ensureRemoteAudio(), {
        onStateChange: s => {
          state.value = s;
          // Si entra/empieza una llamada con el panel oculto, mostrarlo para que el
          // agente pueda contestar/ver la llamada (el botón de ocultar mantiene el
          // registro, así que las entrantes deben poder sacar el panel a la vista).
          if (s === 'calling' || s === 'in_call') {
            isOpen.value = true;
            isMinimized.value = false;
          }
          // Reportar cada cambio de estado al backend (presencia en vivo).
          reportPresence();
        },
        onCallStart: p => {
          markCallAnswered(p?.codec);
          emitter.emit('jabvox.softphone.callStart', p);
        },
        onCallEnd: p => {
          // Si la saliente nunca fue contestada, el estado real es "missed"/no contestada.
          const status = p?.answered === false ? 'missed' : 'ended';
          closeCallLog(status, { endedBy: p?.endedBy });
          emitter.emit('jabvox.softphone.callEnd', p);
        },
        onCallFailed: p => {
          lastError.value = p?.reason || 'call_failed';
          closeCallLog('failed', { reason: p?.reason, code: p?.code });
          emitter.emit('jabvox.softphone.callFailed', p);
        },
      });
      await sip.register();
      connectedAccountId.value = accountId;
      startPresenceHeartbeat();
      return true;
    } catch (error) {
      lastError.value =
        error?.response?.data?.error || error?.message || 'connect_error';
      state.value = 'failed';
      return false;
    }
  };

  /**
   * Obtiene credenciales del backend y registra la extensión de la CUENTA ACTUAL.
   * Reentrante: si ya está registrado con la misma cuenta no hace nada; si hay un
   * registro en curso (p. ej. la pre-conexión al abrir), todos esperan ESE mismo
   * registro en vez de lanzar otro. Así el primer clic en Llamar ya saca la llamada.
   * @returns {Promise<boolean>}
   */
  const connect = async () => {
    const accountId = currentAccountId();
    if (isRegistered.value && connectedAccountId.value === accountId)
      return true;
    if (connectPromise) return connectPromise;

    connectPromise = doConnect(accountId).finally(() => {
      connectPromise = null;
    });
    return connectPromise;
  };

  /**
   * Normaliza el número al formato que espera el dialplan de salida.
   * El plan de marcado del PBX antepone el indicativo de país (57) al número
   * marcado (Macro(dialout-trunk,1,57${EXTEN},...)). Por eso el softphone debe
   * enviar el número LOCAL (10 dígitos), igual que Zoiper: si el usuario escribe
   * o pega el número con +57 / 0057 / 57 delante, lo quitamos para no duplicarlo.
   * @param {string} raw
   * @returns {string}
   */
  const normalizeForDialplan = raw => {
    let n = String(raw || '').replace(/[^\d+*#]/g, '');
    n = n.replace(/^\+/, ''); // fuera el + internacional
    n = n.replace(/^0057/, ''); // 0057 -> local
    // 57 + 10 dígitos (móvil CO) -> quitar el 57. Un número local de 10 dígitos
    // que empiece por 3 (móvil) NO se toca; solo el prefijo país sobrante.
    if (/^57\d{10}$/.test(n)) n = n.slice(2);
    return n;
  };

  /**
   * Realiza una llamada. Conecta primero si hace falta. Fuente de los 3 orígenes:
   * manual (teclado), click-to-call y dialer entran todos por aquí.
   * @param {string} number
   * @param {{name?: string}} [meta]
   */
  const call = async (number, meta = {}) => {
    const target = normalizeForDialplan(number || dialedNumber.value || '');
    if (!target) return;
    currentTarget.value = { name: meta.name || '', phone: target };
    dialedNumber.value = target;
    isOpen.value = true;
    isMinimized.value = false;
    const ok = await connect();
    if (!ok) return;
    await openCallLog(target);
    try {
      await sip.call(target);
    } catch (error) {
      lastError.value = error?.message || 'call_failed';
      closeCallLog('failed', { reason: error?.message });
    }
  };

  /** Cuelga la llamada actual. */
  const hangup = async () => {
    await sip?.hangup();
  };

  /** Agrega un dígito al número marcado; si hay llamada activa, envía DTMF. */
  const pressDigit = digit => {
    if (isInCall.value) {
      sip?.sendDtmf(digit);
    } else {
      dialedNumber.value += digit;
    }
  };

  const backspace = () => {
    dialedNumber.value = dialedNumber.value.slice(0, -1);
  };

  const clearNumber = () => {
    dialedNumber.value = '';
  };

  /** Silencia/activa el micrófono. */
  const toggleMute = () => {
    isMuted.value = !isMuted.value;
    sip?.setMuted(isMuted.value);
  };

  /** Transfiere la llamada a otra extensión. @param {string} target */
  const transfer = target => sip?.transfer(target);

  /** Copia el número marcado desde el portapapeles (pegar). @param {string} text */
  const setDialedNumber = text => {
    // Acepta solo dígitos, +, *, # (sanea al pegar).
    dialedNumber.value = String(text || '').replace(/[^\d+*#]/g, '');
  };

  /** Streams para el visualizador de espectro (mic local + audio remoto). */
  const getLocalStream = () => sip?.getLocalStream() || null;
  const getRemoteStream = () => sip?.getRemoteStream() || null;

  const open = () => {
    isOpen.value = true;
    isMinimized.value = false;
    // Pre-registrar al abrir: cuando el teléfono se muestra debe quedar "Conectado"
    // sin tocar nada, para que la primera llamada salga con un solo clic. Si ya está
    // registrado con la cuenta actual, connect() es idempotente (no hace nada).
    if (!isInCall.value) connect();
  };
  const minimize = () => {
    isMinimized.value = true;
  };
  // Oculta la vista del softphone SIN desconectar del PBX: el agente deja de ver el
  // panel pero sigue registrado y recibiendo llamadas (a diferencia de close(), que
  // desregistra). Lo usa el botón de la pestaña para mostrar/ocultar.
  const hide = () => {
    isOpen.value = false;
  };
  const close = async () => {
    isOpen.value = false;
    if (!isInCall.value) {
      stopPresenceHeartbeat();
      await sip?.disconnect();
      // reportar desconexión final (con el estado ya en 'disconnected')
      reportPresence();
      sip = null;
      connectedAccountId.value = null;
    }
  };

  /**
   * Reacción al cambio de cuenta activa. Si el softphone estaba registrado con otra cuenta
   * y NO hay llamada en curso, lo desconecta para que la próxima llamada use la extensión
   * de la nueva cuenta. Si hay llamada activa, no la corta (se re-registrará al colgar).
   */
  const handleAccountSwitch = async () => {
    if (isInCall.value) return;
    if (sip && connectedAccountId.value !== currentAccountId()) {
      stopPresenceHeartbeat();
      await sip.disconnect();
      reportPresence(); // marca desconectada la extensión de la cuenta anterior
      sip = null;
      connectedAccountId.value = null;
      state.value = 'disconnected';
    }
  };

  return {
    // estado
    state,
    dialedNumber,
    isOpen,
    isMinimized,
    isMuted,
    lastError,
    currentTarget,
    isRegistered,
    isInCall,
    extension,
    // acciones
    connect,
    call,
    hangup,
    pressDigit,
    backspace,
    clearNumber,
    toggleMute,
    transfer,
    setDialedNumber,
    open,
    minimize,
    hide,
    close,
    // historial
    callLogs,
    loadCallLogs,
    // audio (visualizador de espectro)
    getLocalStream,
    getRemoteStream,
    // multi-cuenta
    connectedAccountId,
    currentAccountId,
    handleAccountSwitch,
    // util
    toSnake: useSnakeCase,
  };
}
