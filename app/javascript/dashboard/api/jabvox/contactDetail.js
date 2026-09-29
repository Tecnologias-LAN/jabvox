/* global axios */
import ApiClient from '../ApiClient';

// Detalle completo de un contacto: conversaciones por bandeja, gestiones, pedidos y
// registros. Es lo que antes daba el detalle de lead, ahora colgando del contacto.
const client = new ApiClient('jabvox/contact_detail', { accountScoped: true });

export default {
  // Todo en una llamada: { contact, conversations, managements, orders, records }.
  show: contactId => axios.get(`${client.url}/${contactId}`),
  // Secciones sueltas, para recargar una pestaña sin volver a pedirlo todo.
  managements: contactId => axios.get(`${client.url}/${contactId}/managements`),
  orders: contactId => axios.get(`${client.url}/${contactId}/orders`),
  records: contactId => axios.get(`${client.url}/${contactId}/records`),
  // Nueva gestión tipificada desde la ficha. Se guarda como nota del contacto.
  createManagement: (contactId, payload) =>
    axios.post(`${client.url}/${contactId}/create_management`, payload),
  // Campos personalizados, etapa del ciclo de vida y responsable (columnas propias de
  // Jabvox). `assigneeId` solo viaja cuando se pasa: omitirlo deja el asignado intacto,
  // mandarlo en null lo desasigna.
  updateCustomFields: (
    contactId,
    { customFields, lifecycleStage, assigneeId }
  ) =>
    axios.patch(`${client.url}/${contactId}/update_custom_fields`, {
      custom_fields: customFields,
      lifecycle_stage: lifecycleStage,
      ...(assigneeId === undefined ? {} : { assignee_id: assigneeId }),
    }),
};
