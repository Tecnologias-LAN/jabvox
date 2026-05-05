/* global axios */
import ApiClient from '../ApiClient';

class JabvoxKanbanFunnelsAPI extends ApiClient {
  constructor() {
    super('jabvox/kanban_funnels', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  getById(funnelId) {
    return axios.get(`${this.url}/${funnelId}`);
  }

  create(data) {
    return axios.post(this.url, data);
  }

  update(funnelId, data) {
    return axios.patch(`${this.url}/${funnelId}`, data);
  }

  destroy(funnelId) {
    return axios.delete(`${this.url}/${funnelId}`);
  }

  getBoard(funnelId) {
    return axios.get(`${this.url}/${funnelId}/kanban_board`);
  }

  getStages(funnelId) {
    return axios.get(`${this.url}/${funnelId}/kanban_stages`);
  }

  createStage(funnelId, data) {
    return axios.post(`${this.url}/${funnelId}/kanban_stages`, data);
  }

  updateStage(funnelId, stageId, data) {
    return axios.patch(
      `${this.url}/${funnelId}/kanban_stages/${stageId}`,
      data
    );
  }

  deleteStage(funnelId, stageId) {
    return axios.delete(`${this.url}/${funnelId}/kanban_stages/${stageId}`);
  }

  moveConversation(funnelId, conversationId, stageId) {
    return axios.patch(`${this.url}/${funnelId}/kanban_conversation_stages`, {
      conversation_id: conversationId,
      stage_id: stageId,
    });
  }
}

export default new JabvoxKanbanFunnelsAPI();
