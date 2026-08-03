/* global axios */
import ApiClient from '../ApiClient';

// Voice Broadcast (agente virtual saliente): CRUD de campañas de voz, subida de
// audio, controles (start/pause/resume/stop), monitor en vivo y reporte. Reutiliza
// la lista de contactos de una campaña del marcador (jabvox_dialer_campaign_id).
class JabvoxVoiceBroadcastAPI extends ApiClient {
  constructor() {
    super('jabvox/voice_broadcasts', { accountScoped: true });
  }

  create(payload) {
    return axios.post(this.url, payload);
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, payload);
  }

  // Sube el audio (multipart). El backend transcodifica y despliega al PBX.
  uploadAudio(id, file) {
    const form = new FormData();
    form.append('audio', file);
    return axios.post(`${this.url}/${id}/audio`, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  start(id) {
    return axios.post(`${this.url}/${id}/start`);
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  stop(id) {
    return axios.post(`${this.url}/${id}/stop`);
  }

  liveMonitor(id) {
    return axios.get(`${this.url}/${id}/live_monitor`);
  }

  report(id) {
    return axios.get(`${this.url}/${id}/report`);
  }

  reportCsvUrl(id) {
    return `${this.url}/${id}/report_csv`;
  }
}

export default new JabvoxVoiceBroadcastAPI();
