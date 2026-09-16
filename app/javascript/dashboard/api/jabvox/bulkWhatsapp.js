/* global axios */
import ApiClient from '../ApiClient';

// Serializa los campos de los tipos de plantilla extendidos en un FormData
// (el envío por CSV es multipart). Las claves son las mismas que espera
// Jabvox::BulkWhatsappDispatchService y que usa el envío 1:1, para que ambos
// caminos hablen el mismo formato.
// Ver docs/whatsapp-flows/templates-sending-architecture.md.
const appendExtrasToFormData = (formData, extras = {}) => {
  const { authCode, location, ltoExpirationMs, copyCode, cards } = extras || {};
  if (authCode) formData.append('auth_code', authCode);
  if (copyCode) formData.append('copy_code', copyCode);
  if (ltoExpirationMs) formData.append('lto_expiration_ms', ltoExpirationMs);
  if (location?.latitude && location?.longitude) {
    formData.append('location[latitude]', location.latitude);
    formData.append('location[longitude]', location.longitude);
    if (location.name) formData.append('location[name]', location.name);
    if (location.address)
      formData.append('location[address]', location.address);
  }
  (cards || []).forEach((card, index) => {
    if (card?.header?.media_url) {
      formData.append(
        `cards[${index}][header][media_url]`,
        card.header.media_url
      );
    }
    (card?.buttons || []).forEach((button, buttonIndex) => {
      if (!button?.parameter) return;
      formData.append(
        `cards[${index}][buttons][${buttonIndex}][index]`,
        buttonIndex
      );
      formData.append(
        `cards[${index}][buttons][${buttonIndex}][parameter]`,
        button.parameter
      );
    });
  });
};

// Misma información que appendExtrasToFormData, pero como objeto JSON plano
// (el envío desde leads va en JSON, no multipart).
const extrasAsJson = (extras = {}) => {
  const { authCode, location, ltoExpirationMs, copyCode, cards } = extras || {};
  return {
    auth_code: authCode || undefined,
    copy_code: copyCode || undefined,
    lto_expiration_ms: ltoExpirationMs || undefined,
    location: location?.latitude && location?.longitude ? location : undefined,
    cards: cards?.length ? cards : undefined,
  };
};

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

  // Informes → Plantillas: historial de destinatarios CROSS-batch (todas las
  // plantillas de la cuenta), con filtros de rango de fechas/plantilla/bandeja/
  // estado/búsqueda y paginación.
  getTemplatesReport({
    from,
    to,
    template,
    inboxId,
    status,
    q,
    page = 1,
  } = {}) {
    return axios.get(`${this.url}/templates_report`, {
      params: {
        from,
        to,
        template: template || undefined,
        inbox_id: inboxId || undefined,
        status: status || undefined,
        q: q || undefined,
        page,
      },
    });
  }

  // Descarga el CSV del reporte de plantillas (mismos filtros que la vista).
  downloadTemplatesReportCsv({ from, to, template, inboxId, status, q } = {}) {
    return axios.get(`${this.url}/templates_report.csv`, {
      params: {
        from,
        to,
        template: template || undefined,
        inbox_id: inboxId || undefined,
        status: status || undefined,
        q: q || undefined,
      },
      responseType: 'blob',
    });
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
  send({
    file,
    inboxId,
    senderUserId,
    templateName,
    language,
    variableMap,
    numberColumn,
    headerMedia,
    flowButton,
    country,
    extras,
  }) {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('inbox_id', inboxId);
    formData.append('sender_user_id', senderUserId);
    if (templateName) formData.append('template_name', templateName);
    if (language) formData.append('language', language);
    // Columna del CSV que contiene el número (elegida/confirmada en la UI).
    if (numberColumn) formData.append('number_column', numberColumn);
    // País del envío: de él sale el prefijo de los números que llegan sin él.
    if (country) formData.append('country', country);
    // Media del header (de la plantilla): { media_url, media_type }. El backend lo
    // pone en processed_params.header de cada mensaje.
    if (headerMedia?.media_url) {
      formData.append('header_media[media_url]', headerMedia.media_url);
      formData.append('header_media[media_type]', headerMedia.media_type);
    }
    // Botón FLOW de la plantilla: { index, flow_id }. Meta exige el componente
    // button/flow siempre que la plantilla tenga uno.
    if (flowButton?.flow_id) {
      formData.append('flow_button[index]', flowButton.index);
      formData.append('flow_button[flow_id]', flowButton.flow_id);
    }
    // Tipos de plantilla adicionales (auth/location/carousel/oferta/cupón). Son
    // fijos para todo el envío: el mapeo por columna solo aplica al cuerpo.
    appendExtrasToFormData(formData, extras);
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
    headerMedia,
    flowButton,
    extras,
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
      header_media: headerMedia?.media_url ? headerMedia : undefined,
      flow_button: flowButton?.flow_id ? flowButton : undefined,
      ...extrasAsJson(extras),
    });
  }
}

export default new JabvoxBulkWhatsappAPI();
