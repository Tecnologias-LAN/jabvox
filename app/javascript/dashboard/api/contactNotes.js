import ApiClient from './ApiClient';

class ContactNotes extends ApiClient {
  constructor() {
    super('notes', { accountScoped: true });
    this.contactId = null;
  }

  get url() {
    return `${this.baseUrl()}/contacts/${this.contactId}/notes`;
  }

  get(contactId) {
    this.contactId = contactId;
    return super.get();
  }

  create(contactId, content, contentAttributes = {}) {
    this.contactId = contactId;
    return super.create({ content, content_attributes: contentAttributes });
  }

  delete(contactId, id) {
    this.contactId = contactId;
    return super.delete(id);
  }
}

export default new ContactNotes();
