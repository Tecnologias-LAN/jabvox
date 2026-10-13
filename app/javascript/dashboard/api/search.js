/* global axios */
import ApiClient from './ApiClient';

class SearchAPI extends ApiClient {
  constructor() {
    super('search', { accountScoped: true });
  }

  get({ q }) {
    return axios.get(this.url, {
      params: {
        q,
      },
    });
  }

  contacts({ q, page = 1, since, until }) {
    return axios.get(`${this.url}/contacts`, {
      params: {
        q,
        page: page,
        since,
        until,
      },
    });
  }

  conversations({ q, page = 1, since, until }) {
    return axios.get(`${this.url}/conversations`, {
      params: {
        q,
        page: page,
        since,
        until,
      },
    });
  }

  messages({ q, page = 1, since, until, from, inboxId }) {
    return axios.get(`${this.url}/messages`, {
      params: {
        q,
        page: page,
        since,
        until,
        from,
        inbox_id: inboxId,
      },
    });
  }

  // Búsqueda de mensajes dentro de una conversación o un contacto (texto + transcripción de
  // audio + nombre de adjunto). Pasa conversationId O contactId.
  conversationMessages({ q, conversationId, contactId, page = 1 }) {
    return axios.get(`${this.url}/conversation_messages`, {
      params: {
        q,
        page,
        conversation_id: conversationId,
        contact_id: contactId,
      },
    });
  }
}

export default new SearchAPI();
