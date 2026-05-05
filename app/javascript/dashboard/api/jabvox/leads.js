/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/leads', { accountScoped: true });

export default {
  getAll: (params = {}) => axios.get(client.url, { params }),
  getById: id => axios.get(`${client.url}/${id}`),
  syncContacts: () => axios.post(`${client.url}/sync_contacts`),
  bulkAssign: (leadIds, assigneeId) =>
    axios.patch(`${client.url}/bulk_assign`, {
      lead_ids: leadIds,
      assignee_id: assigneeId,
    }),
  bulkUnassign: leadIds =>
    axios.patch(`${client.url}/bulk_unassign`, { lead_ids: leadIds }),
  forContact: contactId => axios.get(`${client.url}/for_contact/${contactId}`),
  updateContactLead: (contactId, campaignName) =>
    axios.patch(`${client.url}/for_contact/${contactId}`, {
      campaign_name: campaignName,
    }),
};
