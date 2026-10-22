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

  moveConversation(funnelId, conversationId, stageId, position = null) {
    return axios.patch(`${this.url}/${funnelId}/kanban_conversation_stages`, {
      conversation_id: conversationId,
      stage_id: stageId,
      ...(position != null ? { position } : {}),
    });
  }

  moveLead(funnelId, leadId, stageId, position = null) {
    return axios.put(
      `${this.url}/${funnelId}/kanban_conversation_stages/update_lead`,
      {
        lead_id: leadId,
        stage_id: stageId,
        ...(position != null ? { position } : {}),
      }
    );
  }

  // Reordena las columnas (etapas) de un embudo: lista de ids en el nuevo orden.
  reorderStages(funnelId, stageIds) {
    return axios.post(`${this.url}/${funnelId}/kanban_stages/reorder`, {
      stage_ids: stageIds,
    });
  }

  // Reordena las tarjetas dentro de una columna: lista ordenada de
  // { conversation_id } o { lead_id }.
  reorderCards(funnelId, stageId, cards) {
    return axios.post(
      `${this.url}/${funnelId}/kanban_conversation_stages/reorder`,
      { stage_id: stageId, cards }
    );
  }
}

export default new JabvoxKanbanFunnelsAPI();
