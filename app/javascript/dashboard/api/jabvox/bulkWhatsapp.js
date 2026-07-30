/* global axios */
import ApiClient from '../ApiClient';

// Bulk WhatsApp module: config (webhook URL), sender users, send history, and CSV upload.
class JabvoxBulkWhatsappAPI extends ApiClient {
  constructor() {
    super('jabvox/bulk_whatsapp', { accountScoped: true });
  }

  getConfig() {
    return axios.get(`${this.url}/config`);
  }

  updateConfig(data) {
    return axios.patch(`${this.url}/config`, { config: data });
  }

  getBatches() {
    return axios.get(`${this.url}/batches`);
  }

  // Detalle de una ejecución + sus destinatarios (para el reporte). Soporta
  // filtro por estado y búsqueda por nombre/número.
  getBatch(id, { status, q } = {}) {
    return axios.get(`${this.url}/batches/${id}`, { params: { status, q } });
  }

  // URL de descarga del reporte en CSV (para abrir en nueva pestaña / <a download>).
  batchCsvUrl(id) {
    return `${this.url}/batches/${id}.csv`;
  }

  // Clona la audiencia de un batch en uno nuevo (draft) para reenviar.
  reuseBatch(id) {
    return axios.post(`${this.url}/batches/${id}/reuse`);
  }

  getSenders() {
    return axios.get(`${this.url}/batches/senders`);
  }

  // Lead custom-field definitions, to build dynamic filters in the leads picker.
  getLeadFields() {
    return axios.get(`${this.url}/batches/lead_fields`);
  }

  // Server-side option search for one custom field — used when the field's base
  // option list is truncated so every value stays findable from the search box.
  searchFieldValues(key, q) {
    return axios.get(`${this.url}/batches/field_values`, {
      params: { key, q },
    });
  }

  // Uploads the CSV (multipart) plus the chosen inbox, sender user and report email.
  send({ file, inboxId, senderUserId, responseEmail }) {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('inbox_id', inboxId);
    formData.append('sender_user_id', senderUserId);
    formData.append('response_email', responseEmail);
    return axios.post(`${this.url}/batches`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // Send to a selection of existing leads (by explicit ids, or "all matching the filter").
  sendLeads({
    inboxId,
    senderUserId,
    responseEmail,
    all,
    leadIds,
    excludedIds,
    filters,
    templateName,
    language,
    text,
    variableMap,
    sourceBatchId,
  }) {
    return axios.post(`${this.url}/batches`, {
      source: 'leads',
      inbox_id: inboxId,
      sender_user_id: senderUserId,
      response_email: responseEmail,
      all,
      lead_ids: leadIds,
      excluded_ids: excludedIds,
      filters,
      template_name: templateName,
      language,
      text,
      variable_map: variableMap,
      source_batch_id: sourceBatchId,
    });
  }
}

export default new JabvoxBulkWhatsappAPI();
