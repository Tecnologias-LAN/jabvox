/* global axios */
import ApiClient from './ApiClient';

export const buildContactParams = (page, sortAttr, label, search) => {
  let params = `include_contact_inboxes=false&page=${page}&sort=${sortAttr}`;
  if (search) {
    params = `${params}&q=${search}`;
  }
  if (label) {
    params = `${params}&labels[]=${label}`;
  }
  return params;
};

class ContactAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  get(page, sortAttr = 'name', label = '') {
    let requestURL = `${this.url}?${buildContactParams(
      page,
      sortAttr,
      label,
      ''
    )}`;
    return axios.get(requestURL);
  }

  show(id) {
    return axios.get(`${this.url}/${id}?include_contact_inboxes=false`);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}?include_contact_inboxes=false`, data);
  }

  getConversations(contactId, { inboxId } = {}) {
    const params = inboxId ? { inbox_id: inboxId } : {};
    return axios.get(`${this.url}/${contactId}/conversations`, { params });
  }

  getAttachments(contactId, page = 1) {
    return axios.get(`${this.url}/${contactId}/attachments`, {
      params: { page },
    });
  }

  getContactableInboxes(contactId) {
    return axios.get(`${this.url}/${contactId}/contactable_inboxes`);
  }

  getContactLabels(contactId) {
    return axios.get(`${this.url}/${contactId}/labels`);
  }

  initiateCall(contactId, inboxId, conversationId = null) {
    return axios.post(`${this.url}/${contactId}/call`, {
      inbox_id: inboxId,
      conversation_id: conversationId,
    });
  }

  updateContactLabels(contactId, labels) {
    return axios.post(`${this.url}/${contactId}/labels`, { labels });
  }

  search(search = '', page = 1, sortAttr = 'name', label = '', options = {}) {
    let requestURL = `${this.url}/search?${buildContactParams(
      page,
      sortAttr,
      label,
      search
    )}`;
    return axios.get(requestURL, { signal: options.signal });
  }

  active(page = 1, sortAttr = 'name') {
    let requestURL = `${this.url}/active?${buildContactParams(page, sortAttr)}`;
    return axios.get(requestURL);
  }

  // eslint-disable-next-line default-param-last
  filter(page = 1, sortAttr = 'name', queryPayload) {
    let requestURL = `${this.url}/filter?${buildContactParams(page, sortAttr)}`;
    return axios.post(requestURL, queryPayload);
  }

  // El país es obligatorio: de él sale el prefijo telefónico. duplicatePolicy
  // indica qué hacer con los leads que ya existen ('skip' u 'update'), tal como
  // lo confirmó el usuario en la vista previa.
  importContacts(file, { country, duplicatePolicy = 'skip' } = {}) {
    const formData = new FormData();
    formData.append('import_file', file);
    if (country) formData.append('country', country);
    formData.append('duplicate_policy', duplicatePolicy);
    return axios.post(`${this.url}/import`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // Analiza las filas antes de importar: devuelve cuáles son nuevas, cuáles ya
  // existen en la cuenta y cuáles traen el prefijo en el archivo. No escribe nada.
  importPreview({ rows, country }) {
    return axios.post(`${this.url}/import_preview`, { rows, country });
  }

  destroyCustomAttributes(contactId, customAttributes) {
    return axios.post(`${this.url}/${contactId}/destroy_custom_attributes`, {
      custom_attributes: customAttributes,
    });
  }

  destroyAvatar(contactId) {
    return axios.delete(`${this.url}/${contactId}/avatar`);
  }

  exportContacts(queryPayload) {
    return axios.post(`${this.url}/export`, queryPayload);
  }
}

export default new ContactAPI();
