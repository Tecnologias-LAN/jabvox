/* global axios */
import ApiClient from '../ApiClient';

// WhatsApp Groups module (Meta Groups API): eligibility check, group CRUD,
// members/roles, invite link and sending a message to the group.
class JabvoxWhatsappGroupsAPI extends ApiClient {
  constructor() {
    super('jabvox/whatsapp_groups', { accountScoped: true });
  }

  eligibility(inboxId) {
    return axios.get(`${this.url}/inboxes/${inboxId}/eligibility`);
  }

  getGroups() {
    return axios.get(`${this.url}/groups`);
  }

  getGroup(id) {
    return axios.get(`${this.url}/groups/${id}`);
  }

  createGroup({ name, description, inboxId, memberPhones }) {
    return axios.post(`${this.url}/groups`, {
      group: {
        name,
        description,
        inbox_id: inboxId,
        member_phones: memberPhones,
      },
    });
  }

  updateGroup(id, { name, description }) {
    return axios.patch(`${this.url}/groups/${id}`, {
      group: { name, description },
    });
  }

  refreshInvite(id) {
    return axios.post(`${this.url}/groups/${id}/invite`);
  }

  addMember(id, { phoneNumber, role }) {
    return axios.post(`${this.url}/groups/${id}/members`, {
      member: { phone_number: phoneNumber, role },
    });
  }

  removeMember(id, memberId) {
    return axios.delete(`${this.url}/groups/${id}/members/${memberId}`);
  }

  updateMemberRole(id, memberId, role) {
    return axios.patch(`${this.url}/groups/${id}/members/${memberId}`, {
      member: { role },
    });
  }

  sendMessage(id, text) {
    return axios.post(`${this.url}/groups/${id}/messages`, {
      message: { text },
    });
  }
}

export default new JabvoxWhatsappGroupsAPI();
