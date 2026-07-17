/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/leads', { accountScoped: true });

export default {
  getAll: (params = {}) => axios.get(client.url, { params }),
  getById: id => axios.get(`${client.url}/${id}`),
  // All lead ids matching the given filters (whole result, not one page), for
  // "select all filter" bulk actions. Same filter params as getAll.
  matchingIds: (params = {}) =>
    axios.get(`${client.url}/matching_lead_ids`, { params }),
  syncContacts: () => axios.post(`${client.url}/sync_contacts`),
  bulkAssign: (leadIds, assigneeId) =>
    axios.patch(`${client.url}/bulk_assign`, {
      lead_ids: leadIds,
      assignee_id: assigneeId,
    }),
  bulkUnassign: leadIds =>
    axios.patch(`${client.url}/bulk_unassign`, { lead_ids: leadIds }),
  bulkDestroy: leadIds =>
    axios.delete(`${client.url}/bulk_destroy`, { data: { lead_ids: leadIds } }),
  forContact: contactId => axios.get(`${client.url}/for_contact/${contactId}`),
  updateContactLead: (contactId, campaignName) =>
    axios.patch(`${client.url}/for_contact/${contactId}`, {
      campaign_name: campaignName,
    }),
  // Unified edit of the lead detail panel.
  updateDetails: (id, payload) =>
    axios.patch(`${client.url}/${id}/update_details`, payload),
};
