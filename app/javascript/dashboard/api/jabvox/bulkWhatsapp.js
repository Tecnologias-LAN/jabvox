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

  getSenders() {
    return axios.get(`${this.url}/batches/senders`);
  }

  // Lead custom-field definitions, to build dynamic filters in the leads picker.
  getLeadFields() {
    return axios.get(`${this.url}/batches/lead_fields`);
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
    });
  }
}

export default new JabvoxBulkWhatsappAPI();
