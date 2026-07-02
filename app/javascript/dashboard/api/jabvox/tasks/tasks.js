/* global axios */
import ApiClient from '../../ApiClient';

// Tasks (kanban cards).
class JabvoxTasksAPI extends ApiClient {
  constructor() {
    super('jabvox/tasks/tasks', { accountScoped: true });
  }

  getAll(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { task: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { task: data });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  move(id, stageId, position) {
    return axios.post(`${this.url}/${id}/move`, {
      stage_id: stageId,
      position,
    });
  }

  activities(id) {
    return axios.get(`${this.url}/${id}/activities`);
  }

  // Dispatch log of the task's recurring automations (what was sent).
  automationRuns(id) {
    return axios.get(`${this.url}/${id}/automation_runs`);
  }

  // Recurring per-task automations (send email/sms/message every N days/weeks/months).
  listAutomations(taskId) {
    return axios.get(`${this.url}/${taskId}/automations`);
  }

  createAutomation(taskId, data) {
    return axios.post(`${this.url}/${taskId}/automations`, {
      automation: data,
    });
  }

  updateAutomation(taskId, id, data) {
    return axios.patch(`${this.url}/${taskId}/automations/${id}`, {
      automation: data,
    });
  }

  destroyAutomation(taskId, id) {
    return axios.delete(`${this.url}/${taskId}/automations/${id}`);
  }

  runAutomationNow(taskId, id) {
    return axios.post(`${this.url}/${taskId}/automations/${id}/run_now`);
  }
}

export default new JabvoxTasksAPI();
