/* global axios */
import ApiClient from '../ApiClient';

// "WhatsappFlow" / "whatsapp_flows" en todo este cliente — nunca "Flow" a
// secas: ese nombre ya lo usa el módulo de Automations (JabvoxFlow).
//
// El backend monta `resources :flows, path: ''` dentro de
// `namespace :whatsapp_flows` (config/routes.rb), es decir el recurso vive
// directamente en la raíz del namespace (jabvox/whatsapp_flows/:id, sin un
// segmento /flows/ adicional) — confirmado con `rails routes`.
const client = new ApiClient('jabvox/whatsapp_flows', {
  accountScoped: true,
});
const base = client.url;

export const wfFlowsAPI = {
  getAll: params => axios.get(base, { params }),
  get: id => axios.get(`${base}/${id}`),
  create: data => axios.post(base, data),
  update: (id, data) => axios.patch(`${base}/${id}`, data),
  delete: id => axios.delete(`${base}/${id}`),
  // Corre el Validator local (backend), sin tocar Meta.
  validate: id => axios.post(`${base}/${id}/validate`),
  // Valida + compila + crea/actualiza en Meta + publica.
  publish: id => axios.post(`${base}/${id}/publish`),
  // Refresca meta_status/validation_errors_json desde Meta.
  sync: id => axios.post(`${base}/${id}/sync`),
  duplicate: id => axios.post(`${base}/${id}/duplicate`),
  versions: id => axios.get(`${base}/${id}/versions`),
  submissions: (id, params) =>
    axios.get(`${base}/${id}/submissions`, { params }),
  metrics: id => axios.get(`${base}/${id}/metrics`),
  categories: () => axios.get(`${base}/categories`),
};
