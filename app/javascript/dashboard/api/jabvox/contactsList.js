/* global axios */
import ApiClient from '../ApiClient';

// Lista unificada de contactos: la que sustituye a la pantalla de Leads. Mismos filtros que
// aceptaba aquella (q, email, phone, document, country, campaign_id, sold, affiliate_id,
// inbox_id, team_id, status, management_state, date_from/to, custom, sort) más
// `lifecycle_stage`, que sustituye a la distinción "es lead / no es lead".
const client = new ApiClient('jabvox/contacts_list', { accountScoped: true });

export default {
  // Devuelve { contacts, meta: { total, page, per_page }, filter_options }.
  // filter_options solo viaja en la primera página: el frontend conserva su copia al
  // paginar para no repetir 6 consultas por cada página.
  getAll: (params = {}) => axios.get(client.url, { params }),
  // Asigna (o desasigna con assigneeId null) varios contactos a la vez.
  bulkAssign: (contactIds, assigneeId) =>
    axios.patch(`${client.url}/bulk_assign`, {
      contact_ids: contactIds,
      assignee_id: assigneeId,
    }),
  // Catálogo de etapas del ciclo de vida, para los selectores que las ofrecen.
  lifecycleStages: () => axios.get(`${client.url}/lifecycle_stages`),
  // Cambia la etapa del ciclo de vida (prospecto | interesado | cliente | inactivo).
  updateLifecycle: (contactId, stage) =>
    axios.patch(`${client.url}/${contactId}/update_lifecycle`, {
      lifecycle_stage: stage,
    }),
};
