/* global axios */
import ApiClient from '../ApiClient';

// API de "Saldo IA" por cuenta: ver saldo y crear/listar virtual keys. La key en claro solo
// llega en la respuesta de createKey (una vez); Jabvox no la persiste.
class JabvoxAiBudgetAPI extends ApiClient {
  constructor() {
    super('jabvox/ai_budget', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  keys() {
    return axios.get(`${this.url}/keys`);
  }

  createKey(data) {
    return axios.post(`${this.url}/create_key`, data);
  }

  // token_id es el HASH de la key (nunca la key en claro): identifica la key sin exponerla.
  blockKey(tokenId) {
    return axios.post(`${this.url}/block_key`, { token_id: tokenId });
  }

  unblockKey(tokenId) {
    return axios.post(`${this.url}/unblock_key`, { token_id: tokenId });
  }

  // `models` omitido = no se toca; [] = sin restricción (hereda los del team).
  updateKey(tokenId, maxBudgetUsd, models) {
    const payload = { token_id: tokenId };
    if (maxBudgetUsd !== undefined && maxBudgetUsd !== null) {
      payload.max_budget_usd = maxBudgetUsd;
    }
    if (models !== undefined) payload.models = models;
    return axios.post(`${this.url}/update_key`, payload);
  }
}

export const aiBudgetAPI = new JabvoxAiBudgetAPI();
