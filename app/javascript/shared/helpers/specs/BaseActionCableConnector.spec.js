import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import BaseActionCableConnector from '../BaseActionCableConnector';

// La ventana del agente se quedaba muda —sin mensajes nuevos hasta recargar— cuando el
// socket moría sin disparar el callback `disconnected`: `checkConnection` volvía a
// programarse sin intentar reabrir nunca.
describe('BaseActionCableConnector#checkConnection', () => {
  let connector;
  let connection;

  const buildConnector = ({ isOpen }) => {
    connection = {
      isOpen: vi.fn(() => isOpen),
      reopen: vi.fn(),
      open: vi.fn(),
    };
    const instance = Object.create(BaseActionCableConnector.prototype);
    instance.consumer = { connection };
    instance.reconnectTimer = null;
    instance.reconnectDelay = 1000;
    instance.onReconnect = vi.fn();
    // `initReconnectTimer` y `clearReconnectTimer` son campos de instancia (arrow
    // functions), no viven en el prototipo: Object.create no los trae. Se replican aquí
    // con el mismo comportamiento que el original para poder observar el espaciado.
    instance.clearReconnectTimer = () => {
      if (instance.reconnectTimer) {
        clearTimeout(instance.reconnectTimer);
        instance.reconnectTimer = null;
      }
    };
    instance.initReconnectTimer = () => {
      instance.clearReconnectTimer();
      const delay = instance.reconnectDelay || 1000;
      instance.reconnectTimer = setTimeout(
        () => instance.checkConnection(),
        delay
      );
      if (BaseActionCableConnector.isDisconnected) {
        instance.reconnectDelay = Math.min(delay * 2, 10000);
      }
    };
    return instance;
  };

  beforeEach(() => {
    vi.useFakeTimers();
    BaseActionCableConnector.isDisconnected = false;
  });

  afterEach(() => vi.useRealTimers());

  it('reabre el socket cuando está caído, aunque no llegara el callback disconnected', () => {
    connector = buildConnector({ isOpen: false });

    connector.checkConnection();

    expect(connection.reopen).toHaveBeenCalled();
    expect(BaseActionCableConnector.isDisconnected).toBe(true);
  });

  it('no reabre nada si la conexión está sana', () => {
    connector = buildConnector({ isOpen: true });

    connector.checkConnection();

    expect(connection.reopen).not.toHaveBeenCalled();
  });

  it('avisa de la reconexión cuando el socket vuelve tras una caída', () => {
    BaseActionCableConnector.isDisconnected = true;
    connector = buildConnector({ isOpen: true });

    connector.checkConnection();

    expect(connector.onReconnect).toHaveBeenCalled();
    expect(BaseActionCableConnector.isDisconnected).toBe(false);
  });

  // Sin tope, un corte de red largo dispararía un intento por segundo contra el servidor.
  it('espacia los reintentos mientras sigue caído, hasta un máximo', () => {
    connector = buildConnector({ isOpen: false });

    connector.checkConnection();
    const primero = connector.reconnectDelay;
    connector.checkConnection();
    const segundo = connector.reconnectDelay;

    expect(segundo).toBeGreaterThan(primero);
    expect(segundo).toBeLessThanOrEqual(10000);
  });

  it('vuelve al intervalo corto cuando la conexión se restablece', () => {
    connector = buildConnector({ isOpen: false });
    connector.checkConnection();
    expect(connector.reconnectDelay).toBeGreaterThan(1000);

    connection.isOpen = vi.fn(() => true);
    connector.checkConnection();

    expect(connector.reconnectDelay).toBe(1000);
  });
});
