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

  // Reportes agregados: totales + serie por envío/día/semana, con rango opcional.
  getAnalytics({ groupBy = 'batch', from, to } = {}) {
    return axios.get(`${this.url}/batches/analytics`, {
      params: {
        group_by: groupBy,
        from: from || undefined,
        to: to || undefined,
      },
    });
  }

  // Detalle de una ejecución + sus destinatarios (para el reporte). Soporta
  // filtro por estado y búsqueda por nombre/número.
  getBatch(id, { status, q } = {}) {
    return axios.get(`${this.url}/batches/${id}`, { params: { status, q } });
  }

  // Descarga el CSV del reporte vía axios (lleva el api_access_token). window.open no
  // envía ese header y caía en el login de Devise ("You need to sign in").
  downloadBatchCsv(id, { status, q } = {}) {
    return axios.get(`${this.url}/batches/${id}.csv`, {
      params: { status, q },
      responseType: 'blob',
    });
  }

  // Clona la audiencia de un batch en uno nuevo (draft) para reenviar. status: estados a
  // clonar (p. ej. 'failed' o 'failed,pending'); vacío = toda la audiencia.
  reuseBatch(id, { status } = {}) {
    return axios.post(`${this.url}/batches/${id}/reuse`, { status });
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

  // Uploads the CSV (multipart) plus the chosen inbox and sender user. La plantilla,
  // el idioma y el mapeo {{n}}→columna se eligen en la UI y viajan aquí; el archivo
  // solo aporta número, nombre y las columnas de variables.
  send({ file, inboxId, senderUserId, templateName, language, variableMap }) {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('inbox_id', inboxId);
    formData.append('sender_user_id', senderUserId);
    if (templateName) formData.append('template_name', templateName);
    if (language) formData.append('language', language);
    // variable_map es un objeto { "1": "columna" }: se serializa como variable_map[1]=columna.
    Object.entries(variableMap || {}).forEach(([n, col]) => {
      if (col) formData.append(`variable_map[${n}]`, col);
    });
    return axios.post(`${this.url}/batches`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // Send to a selection of existing leads (by explicit ids, or "all matching the filter").
  sendLeads({
    inboxId,
    senderUserId,
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
