/* global axios */
import ApiClient from '../ApiClient';

// Capa de compatibilidad tras retirar Leads: cada método apunta al endpoint de CONTACTOS
// equivalente y devuelve la misma forma que antes, para que las pantallas que aún la
// importan (plantillas, marcador, selector de tareas, envío masivo) sigan funcionando sin
// tocarlas una a una.
//
// Un "lead id" es hoy el id del contacto: la tabla intermedia desapareció y ambos coinciden.
const contactsList = new ApiClient('jabvox/contacts_list', {
  accountScoped: true,
});
const contactDetail = new ApiClient('jabvox/contact_detail', {
  accountScoped: true,
});
const contacts = new ApiClient('contacts', { accountScoped: true });

// Valores planos con el formato que esperaban las pantallas de plantillas: los campos
// personalizados van prefijados con `custom:`, los estándar por su nombre.
const legacyFields = contact => {
  if (!contact) return {};
  const fields = {
    name: contact.name || '',
    email: contact.email || '',
    phone_number: contact.phone_number || '',
  };
  Object.entries(contact.custom_fields || {}).forEach(([key, value]) => {
    fields[`custom:${key}`] = value;
  });
  return fields;
};

// Da forma de "lead" a un contacto, con las claves que esperan las pantallas antiguas.
const asLead = contact =>
  contact && {
    ...contact,
    // El número de lead ya no existe; el id del contacto ocupa su lugar.
    lead_number: contact.id,
    contact_id: contact.id,
    contact,
  };

export default {
  getAll: (params = {}) =>
    axios.get(contactsList.url, { params }).then(res => ({
      ...res,
      data: {
        ...res.data,
        leads: (res.data.contacts || []).map(asLead),
      },
    })),

  getById: id =>
    axios
      .get(`${contactDetail.url}/${id}`)
      .then(res => ({ ...res, data: asLead(res.data.contact) })),

  // Todos los ids que casan con los filtros (no solo una página), para las acciones en lote
  // del tipo "seleccionar todo el filtro".
  matchingIds: (params = {}) =>
    axios
      .get(contactsList.url, { params: { ...params, per_page: 'all' } })
      .then(res => ({
        ...res,
        data: { ids: (res.data.contacts || []).map(c => c.id) },
      })),

  bulkAssign: (leadIds, assigneeId) =>
    axios.patch(`${contactsList.url}/bulk_assign`, {
      contact_ids: leadIds,
      assignee_id: assigneeId,
    }),

  bulkUnassign: leadIds =>
    axios.patch(`${contactsList.url}/bulk_assign`, {
      contact_ids: leadIds,
      assignee_id: null,
    }),

  bulkDestroy: leadIds =>
    axios.post(`${contacts.url}/bulk_destroy`, { contact_ids: leadIds }),

  // `fields` conserva el formato que esperaban las pantallas: los campos personalizados
  // llegan con el prefijo `custom:`, junto a los campos estándar del contacto.
  forContact: contactId =>
    axios.get(`${contactDetail.url}/${contactId}`).then(res => ({
      ...res,
      data: {
        ...asLead(res.data.contact),
        custom_field_defs: res.data.custom_field_defs || [],
        fields: legacyFields(res.data.contact),
      },
    })),

  // Detalle completo de un contacto, que es lo que pinta el panel lateral de la conversación.
  // `lead` lleva los nombres ya resueltos (campaña, afiliado, responsable) porque ese panel
  // los pinta directamente, sin volver a consultarlos.
  detailForContact: contactId =>
    axios.get(`${contactDetail.url}/${contactId}`).then(res => {
      const contact = res.data.contact || {};
      const firstInbox = (res.data.conversations || [])[0]?.inbox;
      const extra = contact.additional_attributes || {};
      return {
        ...res,
        data: {
          ...res.data,
          // El panel lee estos campos PLANOS; en el contacto viven dentro de
          // additional_attributes, así que se aplanan aquí (si no, salían siempre vacíos).
          contact: {
            ...contact,
            phone: contact.phone_number,
            identification: extra.jabvox_identification_number || '',
            contact_type: extra.jabvox_contact_type || '',
            country: extra.country || extra.country_code || '',
            city: extra.city || '',
            bio: extra.description || '',
            company_name: extra.company_name || '',
          },
          lead: {
            ...asLead(contact),
            campaign_name: contact.campaign?.name || '',
            affiliate_name: contact.affiliate?.name || '',
            assignee_name: contact.assignee?.name || '',
          },
          inbox_name: firstInbox?.name || '',
          custom_fields: (res.data.custom_field_defs || []).map(def => ({
            key: def.key,
            label: def.label,
            value: (contact.custom_fields || {})[def.key] || '',
          })),
        },
      };
    }),

  updateContactLead: (contactId, campaignName) =>
    axios.patch(`${contacts.url}/${contactId}`, {
      jabvox_campaign_name: campaignName,
    }),

  updateDetails: (id, payload) => axios.patch(`${contacts.url}/${id}`, payload),

  // Campos personalizados y etapa del ciclo de vida.
  updateCustomFields: (id, customFields) =>
    axios.patch(`${contactDetail.url}/${id}/update_custom_fields`, {
      custom_fields: customFields,
    }),
};
