/* global axios */
import ApiClient from '../ApiClient';

const smtpClient = new ApiClient('jabvox/smtp_config', { accountScoped: true });
const templatesClient = new ApiClient('jabvox/email_templates', {
  accountScoped: true,
});
const calendarSettingClient = new ApiClient('jabvox/calendar_setting', {
  accountScoped: true,
});

export const calendarSettingAPI = {
  get: () => axios.get(calendarSettingClient.url),
  update: data =>
    axios.patch(calendarSettingClient.url, { calendar_setting: data }),
};

export const smtpConfigAPI = {
  get: () => axios.get(smtpClient.url),
  save: data => axios.post(smtpClient.url, { smtp_config: data }),
  update: data => axios.patch(smtpClient.url, { smtp_config: data }),
  destroy: () => axios.delete(smtpClient.url),
  test: () => axios.post(`${smtpClient.url}/test`),
};

export const emailTemplatesAPI = {
  getAll: () => axios.get(templatesClient.url),
  getById: id => axios.get(`${templatesClient.url}/${id}`),
  sendToContact: (id, contactId) =>
    axios.post(`${templatesClient.url}/${id}/send_to_contact`, {
      contact_id: contactId,
    }),
  create: data => axios.post(templatesClient.url, { email_template: data }),
  update: (id, data) =>
    axios.patch(`${templatesClient.url}/${id}`, { email_template: data }),
  destroy: id => axios.delete(`${templatesClient.url}/${id}`),
  sendTest: (id, data) =>
    axios.post(`${templatesClient.url}/${id}/test_send`, data),
};

export const stageAutomationsAPI = {
  getAll: (funnelId, stageId) =>
    axios.get(
      `${templatesClient.baseUrl()}/jabvox/kanban_funnels/${funnelId}/kanban_stages/${stageId}/kanban_stage_automations`
    ),
  create: (funnelId, stageId, data) =>
    axios.post(
      `${templatesClient.baseUrl()}/jabvox/kanban_funnels/${funnelId}/kanban_stages/${stageId}/kanban_stage_automations`,
      { automation: data }
    ),
  update: (funnelId, stageId, id, data) =>
    axios.patch(
      `${templatesClient.baseUrl()}/jabvox/kanban_funnels/${funnelId}/kanban_stages/${stageId}/kanban_stage_automations/${id}`,
      { automation: data }
    ),
  destroy: (funnelId, stageId, id) =>
    axios.delete(
      `${templatesClient.baseUrl()}/jabvox/kanban_funnels/${funnelId}/kanban_stages/${stageId}/kanban_stage_automations/${id}`
    ),
};
