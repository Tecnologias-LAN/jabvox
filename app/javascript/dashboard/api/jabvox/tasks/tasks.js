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
}

export default new JabvoxTasksAPI();
