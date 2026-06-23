/* global axios */
import ApiClient from '../../ApiClient';

// Stage automations (admin-only), nested under board + stage.
class JabvoxTaskStageAutomationsAPI extends ApiClient {
  constructor() {
    super('jabvox/tasks/boards', { accountScoped: true });
  }

  stageUrl(boardId, stageId) {
    return `${this.url}/${boardId}/stages/${stageId}/automations`;
  }

  list(boardId, stageId) {
    return axios.get(this.stageUrl(boardId, stageId));
  }

  create(boardId, stageId, data) {
    return axios.post(this.stageUrl(boardId, stageId), { automation: data });
  }

  update(boardId, stageId, id, data) {
    return axios.patch(`${this.stageUrl(boardId, stageId)}/${id}`, {
      automation: data,
    });
  }

  destroy(boardId, stageId, id) {
    return axios.delete(`${this.stageUrl(boardId, stageId)}/${id}`);
  }
}

export default new JabvoxTaskStageAutomationsAPI();
