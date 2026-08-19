/* global axios */
import ApiClient from '../ApiClient';

/**
 * Cliente de la API del softphone. Obtiene las credenciales efímeras para registrar el
 * marcador WebRTC en el navegador.
 */
class SoftphoneAPI extends ApiClient {
  constructor() {
    super('jabvox/softphone', { accountScoped: true });
  }

  /**
   * GET credenciales efímeras (WSS, SIP URI, ICE/TURN temporales, codecs, TTL).
   * @returns {Promise<import('axios').AxiosResponse>}
   */
  getCredentials() {
    return axios.get(`${this.url}/credentials`);
  }

  /** GET historial de llamadas del usuario (recientes primero). */
  getCallLogs() {
    return axios.get(`${this.url}/call_logs`);
  }

  /** POST registra el inicio de una llamada. */
  createCallLog(payload) {
    return axios.post(`${this.url}/call_logs`, payload);
  }

  /** PATCH actualiza/cierra una llamada (duración, estado). */
  updateCallLog(id, payload) {
    return axios.patch(`${this.url}/call_logs/${id}`, payload);
  }

  /**
   * PATCH heartbeat de presencia: reporta el estado en vivo de la extensión del usuario
   * en la cuenta actual (para el panel de estado del super admin). No crítico.
   * @param {{state: string, error?: string, user_agent_info?: string}} payload
   */
  reportPresence(payload) {
    return axios.patch(`${this.url}/presence`, payload);
  }
}

export default new SoftphoneAPI();
