import { createConsumer } from '@rails/actioncable';

const PRESENCE_INTERVAL = 20000;
const RECONNECT_INTERVAL = 1000;
// Sin tope, un corte de red largo haría un intento de reconexión por segundo contra el
// servidor. El intervalo se dobla en cada intento fallido hasta este máximo, que se
// mantiene corto a propósito: al reconectar se refrescan las conversaciones, y un agente
// en plena conversación no puede quedarse medio minuto sin ver lo que entra.
const MAX_RECONNECT_INTERVAL = 10000;
// Con la conexión sana, el chequeo de salud corre espaciado (no cada segundo) para detectar
// un socket zombi sin gastar: cada 15s es suficiente y el monitor nativo de ActionCable
// (stale ~6s) ya cubre la detección rápida.
const HEALTHY_CHECK_INTERVAL = 15000;

class BaseActionCableConnector {
  static isDisconnected = false;

  constructor(
    app,
    pubsubToken,
    websocketHost = '',
    presenceInterval = PRESENCE_INTERVAL
  ) {
    const websocketURL = websocketHost ? `${websocketHost}/cable` : undefined;

    this.consumer = createConsumer(websocketURL);
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: 'RoomChannel',
        pubsub_token: pubsubToken,
        account_id: app.$store.getters.getCurrentAccountId,
        user_id: app.$store.getters.getCurrentUserID,
      },
      {
        updatePresence() {
          this.perform('update_presence');
        },
        received: this.onReceived,
        // `connected` se dispara en CADA (re)conexión real del socket, incluida la que hace
        // el monitor nativo de ActionCable al detectar un socket "stale" (sin depender de que
        // antes se haya disparado `disconnected`). Si veníamos de una caída, forzamos el
        // onReconnect para refrescar conversaciones y recuperar los mensajes perdidos.
        connected: () => {
          if (BaseActionCableConnector.isDisconnected) {
            BaseActionCableConnector.isDisconnected = false;
            this.reconnectDelay = RECONNECT_INTERVAL;
            this.clearReconnectTimer();
            this.onReconnect();
          }
        },
        disconnected: () => {
          BaseActionCableConnector.isDisconnected = true;
          this.onDisconnected();
          this.initReconnectTimer();
        },
      }
    );
    this.app = app;
    this.events = {};
    this.reconnectTimer = null;
    this.reconnectDelay = RECONNECT_INTERVAL;
    this.isAValidEvent = () => true;
    this.triggerPresenceInterval = () => {
      setTimeout(() => {
        this.subscription.updatePresence();
        this.triggerPresenceInterval();
      }, presenceInterval);
    };
    this.triggerPresenceInterval();
    // Chequeo de salud SIEMPRE activo: así se detecta un socket zombi (que murió sin disparar
    // `disconnected`, típico en red móvil/tablet) y se reabre, sin esperar a ese callback.
    this.initReconnectTimer();
  }

  // Antes, el `else` solo reprogramaba el temporizador: si el socket moría sin que se
  // disparara el callback `disconnected` (cambio de red móvil, portátil que despierta, un
  // proxy que corta en silencio), `isDisconnected` seguía en false y esta comprobación
  // giraba en vacío para siempre. La ventana se quedaba muda —sin mensajes nuevos— hasta
  // que el agente recargaba la página.
  //
  // Ahora una conexión caída se reabre, venga o no acompañada del callback.
  checkConnection() {
    const isConnectionActive = this.consumer.connection.isOpen();

    if (BaseActionCableConnector.isDisconnected && isConnectionActive) {
      this.clearReconnectTimer();
      this.onReconnect();
      BaseActionCableConnector.isDisconnected = false;
      this.reconnectDelay = RECONNECT_INTERVAL;
      return;
    }

    if (isConnectionActive) {
      // Conexión sana: el siguiente intento vuelve a partir del intervalo corto y el chequeo
      // de salud se reprograma espaciado (no cada segundo) para no gastar.
      this.reconnectDelay = RECONNECT_INTERVAL;
      this.scheduleHealthCheck();
      return;
    }

    // Socket caído/zombi: marcar y reabrir.
    BaseActionCableConnector.isDisconnected = true;
    // `reopen` y no `open`: open() no hace nada si el socket figura como "activo", y el
    // caso que deja la ventana muda es justamente un socket zombi —en estado connecting
    // que nunca avanza—. reopen() lo cierra y lo levanta de nuevo.
    this.consumer.connection.reopen();
    this.initReconnectTimer();
  }

  // Reprograma el chequeo de salud cuando la conexión está sana (intervalo largo).
  scheduleHealthCheck = () => {
    this.clearReconnectTimer();
    this.reconnectTimer = setTimeout(() => {
      this.checkConnection();
    }, HEALTHY_CHECK_INTERVAL);
  };

  clearReconnectTimer = () => {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  };

  initReconnectTimer = () => {
    this.clearReconnectTimer();
    const delay = this.reconnectDelay || RECONNECT_INTERVAL;
    this.reconnectTimer = setTimeout(() => {
      this.checkConnection();
    }, delay);
    if (BaseActionCableConnector.isDisconnected) {
      this.reconnectDelay = Math.min(delay * 2, MAX_RECONNECT_INTERVAL);
    }
  };

  // eslint-disable-next-line class-methods-use-this
  onReconnect = () => {};

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {};

  disconnect() {
    this.consumer.disconnect();
  }

  onReceived = ({ event, data } = {}) => {
    if (this.isAValidEvent(data)) {
      if (this.events[event] && typeof this.events[event] === 'function') {
        this.events[event](data);
      }
    }
  };
}

export default BaseActionCableConnector;
