import {
  UserAgent,
  Registerer,
  RegistererState,
  Inviter,
  SessionState,
} from 'sip.js';

/**
 * Estados del softphone.
 * @typedef {'disconnected'|'registering'|'registered'|'calling'|'in_call'|'failed'} SipState
 */

/**
 * Credenciales efímeras que entrega el backend
 * (GET /api/v1/accounts/:id/jabvox/softphone/credentials).
 * @typedef {Object} SipCredentials
 * @property {string} wssUrl        - WebSocket seguro del PBX (wss://...).
 * @property {string} sipDomain     - Dominio SIP.
 * @property {string} sipUri        - sip:usuario@dominio.
 * @property {string} authUser      - Usuario de autenticación SIP.
 * @property {string} sipPassword   - Secreto de registro SIP.
 * @property {string[]} codecs      - Codecs permitidos (opus, alaw, ...).
 * @property {'rfc2833'|'info'|'inband'} dtmfMode - Modo de envío de DTMF.
 * @property {boolean} autoAnswer   - Responder automáticamente entrantes.
 * @property {boolean} transferEnabled - Permite transferir (REFER).
 * @property {Array<Object>} iceServers - STUN/TURN (TURN con credenciales temporales).
 * @property {number} ttl           - Vida de la credencial en segundos.
 */

/**
 * @typedef {Object} SipClientCallbacks
 * @property {(state: SipState) => void} [onStateChange]
 * @property {(payload: Object) => void} [onCallStart]
 * @property {(payload: Object) => void} [onCallEnd]
 * @property {(payload: Object) => void} [onCallFailed]
 */

/**
 * Cliente SIP/WebRTC sobre SIP.js. Encapsula el ciclo completo: conectar el UserAgent al
 * WSS, registrar la extensión, lanzar INVITE, enviar DTMF, transferir y colgar. Expone el
 * estado y emite eventos de llamada para analíticas/webhooks (sin bloquear la llamada).
 *
 * No conoce la UI: la vista lo instancia y reacciona a los callbacks.
 */
export default class SipClient {
  /**
   * @param {SipCredentials} credentials
   * @param {HTMLAudioElement} remoteAudio - Elemento <audio> para el audio remoto.
   * @param {SipClientCallbacks} [callbacks]
   */
  constructor(credentials, remoteAudio, callbacks = {}) {
    /** @type {SipCredentials} */
    this.credentials = credentials;
    /** @type {HTMLAudioElement} */
    this.remoteAudio = remoteAudio;
    /** @type {SipClientCallbacks} */
    this.callbacks = callbacks;
    /** @type {SipState} */
    this.state = 'disconnected';
    /** @type {UserAgent|null} */
    this.userAgent = null;
    /** @type {Registerer|null} */
    this.registerer = null;
    /** @type {import('sip.js').Session|null} */
    this.session = null;
    /** @type {MediaStream|null} Stream de audio remoto de la llamada activa. */
    this.remoteStream = null;
    // Reconexión automática del WSS.
    this.intentionalDisconnect = false;
    this.reconnectAttempts = 0;
    this.reconnectTimer = null;
  }

  /**
   * Conecta al PBX y registra la extensión.
   * @returns {Promise<void>}
   */
  async register() {
    this.#setState('registering');
    try {
      const uri = UserAgent.makeURI(this.credentials.sipUri);
      if (!uri) throw new Error('sip_uri_invalid');

      this.userAgent = new UserAgent({
        uri,
        authorizationUsername: this.credentials.authUser,
        authorizationPassword: this.credentials.sipPassword,
        transportOptions: { server: this.credentials.wssUrl },
        sessionDescriptionHandlerFactoryOptions: {
          peerConnectionConfiguration: {
            iceServers: this.credentials.iceServers || [],
          },
          constraints: { audio: true, video: false },
        },
        delegate: { onInvite: invitation => this.#handleIncoming(invitation) },
      });

      await this.userAgent.start();
      // Reconexión automática: si el WebSocket se cae (red, suspensión del equipo,
      // reinicio del PBX), reconectamos con backoff y re-registramos. Así el softphone
      // "no se cae": se recupera solo sin que el agente tenga que refrescar.
      this.#wireAutoReconnect();
      this.registerer = new Registerer(this.userAgent);
      this.registerer.stateChange.addListener(regState => {
        if (regState === RegistererState.Registered) {
          this.reconnectAttempts = 0;
          this.#setState('registered');
        }
        if (
          regState === RegistererState.Unregistered &&
          this.state === 'registering'
        ) {
          this.#fail('registration_failed');
        }
      });
      // Captura la respuesta SIP real del REGISTER (401/403/408…) para diagnosticar.
      await this.registerer.register({
        requestDelegate: {
          onReject: response => {
            const code = response?.message?.statusCode;
            const phrase = response?.message?.reasonPhrase;
            // eslint-disable-next-line no-console
            console.error(
              `[Jabvox softphone] REGISTER rechazado: ${code} ${phrase}`
            );
            this.#fail(`register_rejected_${code || 'unknown'}`);
          },
        },
      });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Jabvox softphone] Error al registrar:', error);
      this.#fail(error?.message || 'register_error');
      throw error;
    }
  }

  /**
   * Lanza una llamada saliente (INVITE) al número/destino.
   * @param {string} target - Número o extensión destino.
   * @returns {Promise<void>}
   */
  async call(target) {
    if (!this.userAgent) throw new Error('not_registered');
    // Aceptamos registered/calling/in_call (el registro puede reportar estados intermedios).
    if (!['registered', 'calling', 'in_call'].includes(this.state)) {
      this.#fail('not_registered');
      throw new Error('not_registered');
    }

    // Limpia el número: solo dígitos, +, *, # (evita target_invalid por espacios/símbolos).
    const clean = String(target).replace(/[^\d+*#]/g, '');
    const destination = UserAgent.makeURI(
      `sip:${clean}@${this.credentials.sipDomain}`
    );
    if (!destination) {
      this.#fail('target_invalid');
      throw new Error('target_invalid');
    }

    this.session = new Inviter(this.userAgent, destination, {
      sessionDescriptionHandlerOptions: {
        constraints: { audio: true, video: false },
      },
    });
    this.#wireSession(this.session, { direction: 'outbound', target: clean });
    this.#setState('calling');

    try {
      await this.session.invite();
    } catch (error) {
      // Errores típicos: micrófono denegado (NotAllowedError), fallo ICE/SDP, etc.
      // eslint-disable-next-line no-console
      console.error('[Jabvox softphone] INVITE falló:', error);
      this.#fail(SipClient.inviteErrorReason(error));
      throw error;
    }
  }

  /** Traduce el error del INVITE a un motivo corto y legible. */
  static inviteErrorReason(error) {
    const name = error?.name || '';
    if (name === 'NotAllowedError' || name === 'SecurityError')
      return 'mic_permission_denied';
    if (name === 'NotFoundError') return 'mic_not_found';
    if (/getUserMedia|media/i.test(error?.message || '')) return 'media_error';
    return error?.message || 'invite_failed';
  }

  /**
   * Envía un tono DTMF durante una llamada activa.
   * @param {string} tone - Un dígito: 0-9, * o #.
   * @returns {boolean} true si se envió.
   */
  sendDtmf(tone) {
    if (!this.session || this.state !== 'in_call') return false;
    const body = `Signal=${tone}\r\nDuration=100`;
    this.session.info({
      requestOptions: {
        body: {
          contentDisposition: 'render',
          contentType: 'application/dtmf-relay',
          content: body,
        },
      },
    });
    return true;
  }

  /**
   * Transfiere la llamada activa a otra extensión (REFER ciego).
   * @param {string} target - Extensión destino.
   * @returns {Promise<boolean>}
   */
  async transfer(target) {
    if (!this.session || !this.credentials.transferEnabled) return false;
    const uri = UserAgent.makeURI(
      `sip:${target}@${this.credentials.sipDomain}`
    );
    if (!uri) return false;
    await this.session.refer(uri);
    return true;
  }

  /** Silencia/activa el micrófono. @param {boolean} muted */
  setMuted(muted) {
    const pc = this.session?.sessionDescriptionHandler?.peerConnection;
    pc?.getSenders().forEach(sender => {
      if (sender.track && sender.track.kind === 'audio') {
        sender.track.enabled = !muted;
      }
    });
  }

  /** Cuelga la llamada actual (o cancela si aún está sonando). */
  async hangup() {
    if (!this.session) return;
    // Marcar que el corte lo inicia el AGENTE (local); el evento Terminated leerá esto
    // para reportar "quién colgó". No anulamos this.session aquí: lo hace #wireSession
    // al recibir Terminated, para no perder la referencia antes de leer la bandera.
    this.session.jabvoxHangupBy = 'agent';
    const { state } = this.session;
    if (state === SessionState.Establishing || state === SessionState.Initial) {
      await this.session.cancel();
    } else if (state === SessionState.Established) {
      await this.session.bye();
    }
  }

  /** Desregistra y cierra la conexión. */
  async disconnect() {
    this.intentionalDisconnect = true; // no reconectar tras un cierre deliberado
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    try {
      await this.hangup();
      await this.registerer?.unregister();
      await this.userAgent?.stop();
    } finally {
      this.#setState('disconnected');
    }
  }

  /**
   * Cablea la reconexión automática del transporte WSS. Si el WebSocket se cierra sin que
   * lo hayamos pedido, reintenta con backoff exponencial (2s, 4s, 8s… tope 30s) hasta
   * volver a conectar y re-registrar. Es lo que hace que el softphone "no se caiga".
   */
  #wireAutoReconnect() {
    const transport = this.userAgent?.transport;
    if (!transport) return;
    transport.onDisconnect = error => {
      if (this.intentionalDisconnect) return;
      // eslint-disable-next-line no-console
      console.warn(
        '[Jabvox softphone] WSS caído, reintentando…',
        error?.message || ''
      );
      this.#scheduleReconnect();
    };
  }

  #scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectAttempts = (this.reconnectAttempts || 0) + 1;
    // Backoff exponencial (2s, 4s, 8s… tope 30s) MÁS jitter aleatorio (0–1s). Sin el
    // jitter, si el PBX se reinicia TODOS los agentes reconectan en el mismo instante
    // (2s, 4s…) y lo saturan con una tormenta de REGISTER sincronizados. El jitter
    // dispersa esa carga — clave con decenas/cientos de softphones conectados.
    const base = Math.min(2000 * 2 ** (this.reconnectAttempts - 1), 30000);
    const delay = base + Math.floor(Math.random() * 1000);
    this.#setState('registering');
    this.reconnectTimer = setTimeout(async () => {
      this.reconnectTimer = null;
      try {
        await this.userAgent.reconnect();
        // reconnect() reabre el WS; re-registramos para refrescar el contacto.
        await this.registerer?.register();
      } catch (e) {
        this.#scheduleReconnect(); // sigue reintentando con más backoff
      }
    }, delay);
  }

  /**
   * MediaStream del MICRÓFONO local de la llamada activa (para el visualizador de espectro).
   * @returns {MediaStream|null}
   */
  getLocalStream() {
    const pc = this.session?.sessionDescriptionHandler?.peerConnection;
    if (!pc) return null;
    const stream = new MediaStream();
    pc.getSenders().forEach(sender => {
      if (sender.track && sender.track.kind === 'audio') {
        stream.addTrack(sender.track);
      }
    });
    return stream.getAudioTracks().length ? stream : null;
  }

  /**
   * MediaStream del audio REMOTO de la llamada activa (para el visualizador de espectro).
   * @returns {MediaStream|null}
   */
  getRemoteStream() {
    const stream = this.remoteStream || this.remoteAudio?.srcObject || null;
    return stream && stream.getAudioTracks?.().length ? stream : null;
  }

  // === privados ===

  /** @param {import('sip.js').Invitation} invitation */
  #handleIncoming(invitation) {
    this.session = invitation;
    this.#wireSession(invitation, { direction: 'inbound' });
    if (this.credentials.autoAnswer) {
      // Aceptar CON las constraints de audio explícitas (igual que la saliente). Sin
      // esto, el navegador podía no capturar el micrófono en la llamada ENTRANTE del
      // dialer → audio unidireccional ("se escucha mal / no me oyen"). Es la llamada
      // que reciben los agentes, así que esto afecta a todos.
      invitation.accept({
        sessionDescriptionHandlerOptions: {
          constraints: { audio: true, video: false },
        },
      });
    }
    // La UI decide aceptar/rechazar si no hay autorespuesta (vía onCallStart).
  }

  /**
   * Cablea los eventos de una sesión (entrante o saliente) a estado + callbacks.
   * @param {import('sip.js').Session} session
   * @param {{direction: 'inbound'|'outbound', target?: string}} meta
   */
  #wireSession(session, meta) {
    // Engancha el audio remoto LO ANTES POSIBLE: el sessionDescriptionHandler (y su
    // peerConnection) se crea al invitar/aceptar, y los tracks remotos pueden llegar
    // por `ontrack` ANTES del estado Established. Si esperábamos a Established para
    // poner el ontrack, ese primer track se perdía → el agente no escuchaba al cliente.
    this.#bindRemoteAudioEarly(session);
    session.stateChange.addListener(async sessionState => {
      if (sessionState === SessionState.Established) {
        session.jabvoxWasEstablished = true;
        this.#attachRemoteAudio(session);
        this.#setState('in_call');
        const codec = await SipClient.negotiatedCodec(session);
        this.#emit('onCallStart', { ...meta, codec, at: Date.now() });
      }
      if (sessionState === SessionState.Terminated) {
        // Quién colgó: si hangup() marcó la bandera, fue el agente; si no, el remoto.
        // Si nunca llegó a Established en una saliente, la otra parte no contestó.
        const answered = session.jabvoxWasEstablished === true;
        const endedBy = session.jabvoxHangupBy || 'remote';
        this.#emit('onCallEnd', {
          ...meta,
          at: Date.now(),
          endedBy,
          answered,
        });
        this.session = null;
        this.remoteStream = null;
        if (this.remoteAudio) this.remoteAudio.srcObject = null;
        if (this.state !== 'disconnected') this.#setState('registered');
      }
    });
  }

  /**
   * Codec de audio negociado (opus/PCMA/…), leído de las WebRTC stats. Devuelve null si no
   * se puede determinar (no crítico).
   */
  static async negotiatedCodec(session) {
    const pc = session.sessionDescriptionHandler?.peerConnection;
    if (!pc?.getStats) return null;
    try {
      const stats = await pc.getStats();
      let codecId = null;
      stats.forEach(r => {
        if (r.type === 'outbound-rtp' && r.kind === 'audio' && r.codecId)
          codecId = r.codecId;
      });
      let name = null;
      stats.forEach(r => {
        if (r.type === 'codec' && r.id === codecId)
          name = r.mimeType?.split('/')?.[1] || null;
      });
      return name;
    } catch (e) {
      return null;
    }
  }

  /**
   * Conecta el audio remoto al elemento <audio>. Los tracks remotos pueden no estar
   * presentes en el instante de "Established" (llegan por el evento ontrack un poco
   * después), así que: (1) armamos el stream con lo que haya ahora, y (2) escuchamos
   * ontrack para agregar los tracks que lleguen luego. Guardamos el stream en
   * this.remoteStream para que el visualizador de espectro lea SIEMPRE el remoto real.
   */
  // Engancha `ontrack` en cuanto exista el peerConnection, aunque la sesión aún no
  // esté Established. El sessionDescriptionHandler se crea de forma asíncrona, así que
  // reintentamos brevemente hasta que aparezca. Idempotente con #attachRemoteAudio (el
  // stream se comparte por this.remoteStream).
  #bindRemoteAudioEarly(session, attempt = 0) {
    const pc = session.sessionDescriptionHandler?.peerConnection;
    if (!pc) {
      // El handler todavía no existe; reintentar unas pocas veces (máx ~1s).
      if (attempt < 20 && this.session === session) {
        setTimeout(() => this.#bindRemoteAudioEarly(session, attempt + 1), 50);
      }
      return;
    }
    if (pc.jabvoxOntrackBound) return;
    pc.jabvoxOntrackBound = true;
    this.#ensureRemoteStream();
    pc.addEventListener('track', event => this.#onRemoteTrack(event));
    // Por si algún track ya llegó antes de enganchar el listener.
    this.#collectExistingReceivers(pc);
  }

  #ensureRemoteStream() {
    if (!this.remoteStream) this.remoteStream = new MediaStream();
    return this.remoteStream;
  }

  #collectExistingReceivers(pc) {
    const stream = this.#ensureRemoteStream();
    pc.getReceivers().forEach(receiver => {
      const track = receiver.track;
      if (track && track.kind === 'audio' && !stream.getTrackById(track.id)) {
        stream.addTrack(track);
      }
    });
    this.#flushRemoteAudio();
  }

  #onRemoteTrack(event) {
    const track =
      event.track || (event.streams && event.streams[0]?.getAudioTracks?.()[0]);
    if (!track || track.kind !== 'audio') return;
    const stream = this.#ensureRemoteStream();
    if (!stream.getTrackById(track.id)) stream.addTrack(track);
    this.#flushRemoteAudio();
  }

  #flushRemoteAudio() {
    if (!this.remoteAudio || !this.remoteStream) return;
    if (this.remoteAudio.srcObject !== this.remoteStream) {
      this.remoteAudio.srcObject = this.remoteStream;
    }
    this.remoteAudio.play().catch(() => {});
  }

  #attachRemoteAudio(session) {
    const pc = session.sessionDescriptionHandler?.peerConnection;
    if (!pc || !this.remoteAudio) return;
    // Asegura el enganche y recoge cualquier receiver ya presente (respaldo del
    // #bindRemoteAudioEarly, por si el handler apareció justo en Established).
    this.#bindRemoteAudioEarly(session);
    this.#collectExistingReceivers(pc);
  }

  /** @param {SipState} state */
  #setState(state) {
    this.state = state;
    this.callbacks.onStateChange?.(state);
  }

  /** @param {string} reason */
  #fail(reason) {
    this.#setState('failed');
    this.#emit('onCallFailed', { reason, at: Date.now() });
  }

  /**
   * @param {'onCallStart'|'onCallEnd'|'onCallFailed'} event
   * @param {Object} payload
   */
  #emit(event, payload) {
    this.callbacks[event]?.(payload);
  }
}
