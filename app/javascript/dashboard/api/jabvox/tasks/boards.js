/* global axios */
import ApiClient from '../../ApiClient';

// Tasks boards (kanban boards) and their nested stages + stage automations.
class JabvoxTasksBoardsAPI extends ApiClient {
  constructor() {
    super('jabvox/tasks/boards', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { board: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { board: data });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // Stages (nested under a board)
  listStages(boardId) {
    return axios.get(`${this.url}/${boardId}/stages`);
  }

  createStage(boardId, data) {
    return axios.post(`${this.url}/${boardId}/stages`, { stage: data });
  }

  updateStage(boardId, stageId, data) {
    return axios.patch(`${this.url}/${boardId}/stages/${stageId}`, {
      stage: data,
    });
  }

  destroyStage(boardId, stageId) {
    return axios.delete(`${this.url}/${boardId}/stages/${stageId}`);
  }

  // Nuevo orden de las columnas del tablero. El backend deriva la posición del índice en
  // la lista, así que aquí solo viajan los ids en el orden deseado.
  reorderStages(boardId, stageIds) {
    return axios.post(`${this.url}/${boardId}/stages/reorder`, {
      stage_ids: stageIds,
    });
  }

  // Destinos de la copia por responsable: a qué tablero suyo va la tarea.
  listAssigneeTargets(boardId) {
    return axios.get(`${this.url}/${boardId}/assignee_board_targets`);
  }

  // Tableros que tienen dueño, para elegir destino.
  ownedBoards(boardId) {
    return axios.get(
      `${this.url}/${boardId}/assignee_board_targets/available_boards`
    );
  }

  createAssigneeTarget(boardId, data) {
    return axios.post(`${this.url}/${boardId}/assignee_board_targets`, {
      target: data,
    });
  }

  updateAssigneeTarget(boardId, id, data) {
    return axios.patch(`${this.url}/${boardId}/assignee_board_targets/${id}`, {
      target: data,
    });
  }

  destroyAssigneeTarget(boardId, id) {
    return axios.delete(`${this.url}/${boardId}/assignee_board_targets/${id}`);
  }
}

export default new JabvoxTasksBoardsAPI();
