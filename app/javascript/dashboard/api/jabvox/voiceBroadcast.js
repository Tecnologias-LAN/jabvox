/* global axios */
import ApiClient from '../ApiClient';

// Voice Broadcast (agente virtual saliente): CRUD de campañas de voz, subida de
// audio, controles (start/pause/resume/stop), monitor en vivo, reporte, historial y
// analítica. Módulo INDEPENDIENTE del marcador: tiene sus propios endpoints de
// catálogo/conteo/preview de leads (colección). Solo requiere el módulo VoIP.
class JabvoxVoiceBroadcastAPI extends ApiClient {
  constructor() {
    super('jabvox/voice_broadcasts', { accountScoped: true });
  }

  // ── Catálogo/conteo/preview de leads (colección, sin campaña guardada) ──────

  // Definiciones de campos personalizados del lead (para filtrar).
  leadFields() {
    return axios.get(`${this.url}/lead_fields`);
  }

  // Valores distintos de un campo custom (autocompletado server-side).
  fieldValues(key, q) {
    return axios.get(`${this.url}/field_values`, { params: { key, q } });
  }

  // Conteo de leads que matchean el payload de filtros (en vivo, antes de guardar).
  filterLeadCount(params) {
    return axios.get(`${this.url}/filter_lead_count`, { params });
  }

  // Lista paginada de leads que matchean el payload de filtros.
  filterPreviewLeads(params) {
    return axios.get(`${this.url}/filter_preview_leads`, { params });
  }

  // Todos los ids que matchean (para "deseleccionar todos").
  matchingLeadIds(params) {
    return axios.get(`${this.url}/matching_lead_ids`, { params });
  }

  // ── Historial y reportes globales (cross-campaña) ───────────────────────────

  history(params) {
    return axios.get(`${this.url}/history`, { params });
  }

  analytics(params) {
    return axios.get(`${this.url}/analytics`, { params });
  }

  analyticsCsvUrl() {
    return `${this.url}/analytics_csv`;
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

  // Conteo de leads que matchean los filtros de la campaña de voz (source 'leads').
  leadCount(id) {
    return axios.get(`${this.url}/${id}/lead_count`);
  }

  // Lista paginada de leads que matchean, para revisar antes de arrancar.
  previewLeads(id, page = 1) {
    return axios.get(`${this.url}/${id}/preview_leads`, { params: { page } });
  }

  report(id) {
    return axios.get(`${this.url}/${id}/report`);
  }

  // Detalle por destinatario, paginado y filtrable (status/outcome). Para el monitor
  // en tiempo real: en qué va, cuántos llamó, cuáles faltan.
  recipients(id, { page = 1, status = '', outcome = '' } = {}) {
    return axios.get(`${this.url}/${id}/recipients`, {
      params: { page, status, outcome },
    });
  }

  reportCsvUrl(id) {
    return `${this.url}/${id}/report_csv`;
  }
}

export default new JabvoxVoiceBroadcastAPI();
