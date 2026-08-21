/* global axios */
import ApiClient from '../ApiClient';

// Billing DENTRO de la app (autenticado, account-scoped).
//   status   -> estado de pago de la cuenta (para el modal de bloqueo)
//   checkout -> inicia el pago de un plan y devuelve la checkout_url de la pasarela
class JabvoxBillingAPI extends ApiClient {
  constructor() {
    super('jabvox/billing', { accountScoped: true });
  }

  getStatus() {
    return axios.get(`${this.url}/status`);
  }

  createCheckout(planId) {
    return axios.post(`${this.url}/checkout`, { plan_id: planId });
  }

  getPayments() {
    return axios.get(`${this.url}/payments`);
  }
}

export default new JabvoxBillingAPI();
