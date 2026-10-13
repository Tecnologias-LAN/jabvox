import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import {
  tasksBoardsAPI,
  tasksAPI,
  taskLeadContactsAPI,
  taskStageAutomationsAPI,
} from 'dashboard/api/jabvox/tasks';

// Mismo criterio que el backend (`scope :ordered`): por posición, y el id desempata para
// que dos columnas con la misma posición no bailen entre recargas.
const sortStages = stages =>
  [...stages].sort(
    (a, b) => (a.position_jabvox ?? 0) - (b.position_jabvox ?? 0) || a.id - b.id
  );

export const useTasksStore = defineStore('jabvoxTasks', {
  state: () => ({
    boards: [],
    currentBoard: null,
    tasks: [],
    leadContacts: [],
    uiFlags: {
      fetchingBoards: false,
      fetchingBoard: false,
      fetchingTasks: false,
      fetchingContacts: false,
      saving: false,
    },
  }),

  getters: {
    boardList: state => camelcaseKeys(state.boards, { deep: true }),
    board: state => camelcaseKeys(state.currentBoard, { deep: true }),
    stages: state =>
      camelcaseKeys(state.currentBoard?.stages || [], { deep: true }),
    taskList: state => camelcaseKeys(state.tasks, { deep: true }),
    contactList: state => camelcaseKeys(state.leadContacts, { deep: true }),
    tasksByStage: state => {
      const grouped = {};
      const camelTasks = camelcaseKeys(state.tasks, { deep: true });
      camelTasks.forEach(task => {
        if (!grouped[task.stageId]) grouped[task.stageId] = [];
        grouped[task.stageId].push(task);
      });
      // Mismo criterio que el backend (`scope :ordered`): por posición y, a igualdad de
      // posición, por fecha de creación (desempate por id como último recurso). Sin este
      // desempate dos tarjetas con la misma posición bailaban entre recargas y el orden se
      // percibía como aleatorio.
      Object.keys(grouped).forEach(key => {
        grouped[key].sort(
          (a, b) =>
            (a.positionJabvox ?? 0) - (b.positionJabvox ?? 0) ||
            new Date(a.createdAt) - new Date(b.createdAt) ||
            a.id - b.id
        );
      });
      return grouped;
    },
  },

  actions: {
    // Boards -----------------------------------------------------------
    async fetchBoards() {
      this.uiFlags.fetchingBoards = true;
      try {
        const { data } = await tasksBoardsAPI.getAll();
        this.boards = data;
        return camelcaseKeys(data, { deep: true });
      } finally {
        this.uiFlags.fetchingBoards = false;
      }
    },

    async getBoard(id) {
      this.uiFlags.fetchingBoard = true;
      try {
        const { data } = await tasksBoardsAPI.show(id);
        this.currentBoard = data;
        return camelcaseKeys(data, { deep: true });
      } finally {
        this.uiFlags.fetchingBoard = false;
      }
    },

    async createBoard(payload) {
      this.uiFlags.saving = true;
      try {
        const { data } = await tasksBoardsAPI.create(payload);
        this.boards.push(data);
        return camelcaseKeys(data, { deep: true });
      } finally {
        this.uiFlags.saving = false;
      }
    },

    async updateBoard(id, payload) {
      const { data } = await tasksBoardsAPI.update(id, payload);
      const idx = this.boards.findIndex(b => b.id === Number(id));
      if (idx !== -1) this.boards.splice(idx, 1, data);
      if (this.currentBoard && this.currentBoard.id === Number(id)) {
        this.currentBoard = { ...this.currentBoard, ...data };
      }
      return camelcaseKeys(data, { deep: true });
    },

    // Copia por responsable: destinos --------------------------------
    async fetchAssigneeTargets(boardId) {
      const { data } = await tasksBoardsAPI.listAssigneeTargets(boardId);
      return camelcaseKeys(data, { deep: true });
    },

    async fetchOwnedBoards(boardId) {
      const { data } = await tasksBoardsAPI.ownedBoards(boardId);
      return camelcaseKeys(data, { deep: true });
    },

    async createAssigneeTarget(boardId, payload) {
      const { data } = await tasksBoardsAPI.createAssigneeTarget(
        boardId,
        payload
      );
      return camelcaseKeys(data, { deep: true });
    },

    async updateAssigneeTarget(boardId, id, payload) {
      const { data } = await tasksBoardsAPI.updateAssigneeTarget(
        boardId,
        id,
        payload
      );
      return camelcaseKeys(data, { deep: true });
    },

    async deleteAssigneeTarget(boardId, id) {
      await tasksBoardsAPI.destroyAssigneeTarget(boardId, id);
    },

    async deleteBoard(id) {
      await tasksBoardsAPI.destroy(id);
      this.boards = this.boards.filter(b => b.id !== Number(id));
    },

    // Stages -----------------------------------------------------------
    // El backend sirve las columnas por position_jabvox. Al insertar o actualizar una en
    // memoria hay que reordenar igual, o el tablero las pinta en el orden en que llegaron
    // al array y el orden visual deja de coincidir con el guardado.
    async createStage(boardId, payload) {
      const { data } = await tasksBoardsAPI.createStage(boardId, payload);
      if (this.currentBoard && this.currentBoard.id === Number(boardId)) {
        const stages = this.currentBoard.stages || [];
        this.currentBoard = {
          ...this.currentBoard,
          stages: sortStages([...stages, data]),
        };
      }
      return camelcaseKeys(data, { deep: true });
    },

    async updateStage(boardId, stageId, payload) {
      const { data } = await tasksBoardsAPI.updateStage(
        boardId,
        stageId,
        payload
      );
      if (this.currentBoard && this.currentBoard.stages) {
        const stages = [...this.currentBoard.stages];
        const idx = stages.findIndex(s => s.id === Number(stageId));
        if (idx !== -1) stages.splice(idx, 1, data);
        this.currentBoard = {
          ...this.currentBoard,
          stages: sortStages(stages),
        };
      }
      return camelcaseKeys(data, { deep: true });
    },

    // Reordenar es optimista: la columna salta al soltarla y, si el servidor rechaza,
    // se restaura el orden previo. Arrastrar y esperar una ida y vuelta se siente roto.
    async reorderStages(boardId, stageIds) {
      const previous = this.currentBoard?.stages
        ? [...this.currentBoard.stages]
        : null;
      if (previous) {
        const byId = new Map(previous.map(s => [s.id, s]));
        const reordered = stageIds.map(id => byId.get(id)).filter(Boolean);
        this.currentBoard = {
          ...this.currentBoard,
          stages: reordered.map((s, i) => ({ ...s, position_jabvox: i })),
        };
      }
      try {
        const { data } = await tasksBoardsAPI.reorderStages(boardId, stageIds);
        if (this.currentBoard) {
          this.currentBoard = {
            ...this.currentBoard,
            stages: sortStages(data),
          };
        }
        return camelcaseKeys(data, { deep: true });
      } catch (error) {
        if (previous) {
          this.currentBoard = { ...this.currentBoard, stages: previous };
        }
        throw error;
      }
    },

    async deleteStage(boardId, stageId) {
      await tasksBoardsAPI.destroyStage(boardId, stageId);
      if (this.currentBoard && this.currentBoard.stages) {
        this.currentBoard = {
          ...this.currentBoard,
          stages: this.currentBoard.stages.filter(
            s => s.id !== Number(stageId)
          ),
        };
      }
    },

    // Tasks ------------------------------------------------------------
    async fetchTasks(params = {}) {
      this.uiFlags.fetchingTasks = true;
      try {
        const { data } = await tasksAPI.getAll(params);
        this.tasks = data;
        return camelcaseKeys(data, { deep: true });
      } finally {
        this.uiFlags.fetchingTasks = false;
      }
    },

    async createTask(payload) {
      this.uiFlags.saving = true;
      try {
        const { data } = await tasksAPI.create(payload);
        this.tasks.push(data);
        return camelcaseKeys(data, { deep: true });
      } finally {
        this.uiFlags.saving = false;
      }
    },

    async updateTask(id, payload) {
      this.uiFlags.saving = true;
      try {
        const { data } = await tasksAPI.update(id, payload);
        const idx = this.tasks.findIndex(tk => tk.id === Number(id));
        if (idx !== -1) this.tasks.splice(idx, 1, data);
        return camelcaseKeys(data, { deep: true });
      } finally {
        this.uiFlags.saving = false;
      }
    },

    async moveTask(id, stageId, position) {
      const taskId = Number(id);
      // Actualización optimista: se mueve la tarjeta a la columna destino en la posición
      // indicada y se reindexan las posiciones de esa columna (0..n), igual que hace el
      // backend. Así la tarjeta aterriza de inmediato en su sitio y no comparte posición
      // con ninguna otra mientras llega la respuesta.
      this.applyLocalMove(taskId, stageId, position);

      const { data } = await tasksAPI.move(id, stageId, position);
      // El backend devuelve la tarjeta ya con su stage/posición definitivos; se reconcilia
      // por si el reindexado del servidor difiere del optimista (p. ej. filas concurrentes).
      const after = this.tasks.findIndex(tk => tk.id === taskId);
      if (after !== -1) this.tasks.splice(after, 1, data);
      return camelcaseKeys(data, { deep: true });
    },

    // Reordena localmente la columna destino tras mover una tarjeta: la inserta en
    // `position` entre las demás de ese stage y reescribe `position_jabvox` de todas a
    // 0..n-1, replicando `reorder_within_stage!` del backend.
    applyLocalMove(taskId, stageId, position) {
      const idx = this.tasks.findIndex(tk => tk.id === taskId);
      if (idx === -1) return;
      this.tasks[idx] = {
        ...this.tasks[idx],
        stage_id: stageId,
        position_jabvox: position,
      };
      const siblings = this.tasks
        .filter(tk => tk.stage_id === stageId && tk.id !== taskId)
        .sort(
          (a, b) =>
            (a.position_jabvox ?? 0) - (b.position_jabvox ?? 0) ||
            new Date(a.created_at) - new Date(b.created_at) ||
            a.id - b.id
        );
      const pos = Math.min(
        Math.max(position ?? siblings.length, 0),
        siblings.length
      );
      siblings.splice(pos, 0, this.tasks[idx]);
      siblings.forEach((tk, i) => {
        const at = this.tasks.findIndex(t => t.id === tk.id);
        if (at !== -1) {
          this.tasks[at] = { ...this.tasks[at], position_jabvox: i };
        }
      });
    },

    async deleteTask(id) {
      await tasksAPI.destroy(id);
      this.tasks = this.tasks.filter(tk => tk.id !== Number(id));
    },

    async restoreTask(id) {
      const { data } = await tasksAPI.restore(id);
      return camelcaseKeys(data, { deep: true });
    },

    // Fetch a single task (used by the detail/history view).
    async getTask(id) {
      const { data } = await tasksAPI.show(id);
      const idx = this.tasks.findIndex(tk => tk.id === Number(id));
      if (idx !== -1) this.tasks.splice(idx, 1, data);
      return camelcaseKeys(data, { deep: true });
    },

    // Append-only activity history for a task (newest first).
    async fetchTaskActivities(id) {
      const { data } = await tasksAPI.activities(id);
      return camelcaseKeys(data, { deep: true });
    },

    // Añade un comentario y devuelve la actividad creada, para insertarla en el
    // historial sin tener que recargarlo entero.
    async addTaskComment(id, body) {
      const { data } = await tasksAPI.comment(id, body);
      return camelcaseKeys(data, { deep: true });
    },

    // Recurring per-task automations -----------------------------------
    async fetchTaskAutomations(taskId) {
      const { data } = await tasksAPI.listAutomations(taskId);
      return camelcaseKeys(data, { deep: true });
    },

    async createTaskAutomation(taskId, payload) {
      const { data } = await tasksAPI.createAutomation(taskId, payload);
      return camelcaseKeys(data, { deep: true });
    },

    async updateTaskAutomation(taskId, id, payload) {
      const { data } = await tasksAPI.updateAutomation(taskId, id, payload);
      return camelcaseKeys(data, { deep: true });
    },

    async deleteTaskAutomation(taskId, id) {
      await tasksAPI.destroyAutomation(taskId, id);
    },

    async runTaskAutomationNow(taskId, id) {
      const { data } = await tasksAPI.runAutomationNow(taskId, id);
      return camelcaseKeys(data, { deep: true });
    },

    // Dispatch log (what each automation has sent) for the task.
    async fetchTaskAutomationRuns(taskId) {
      const { data } = await tasksAPI.automationRuns(taskId);
      return camelcaseKeys(data, { deep: true });
    },

    // Lead contacts ----------------------------------------------------
    async fetchLeadContacts(leadId) {
      this.uiFlags.fetchingContacts = true;
      try {
        const { data } = await taskLeadContactsAPI.getAll({ lead_id: leadId });
        this.leadContacts = data;
        return camelcaseKeys(data, { deep: true });
      } finally {
        this.uiFlags.fetchingContacts = false;
      }
    },

    async createLeadContact(payload) {
      const { data } = await taskLeadContactsAPI.create(payload);
      this.leadContacts.push(data);
      return camelcaseKeys(data, { deep: true });
    },

    async updateLeadContact(id, payload) {
      const { data } = await taskLeadContactsAPI.update(id, payload);
      const idx = this.leadContacts.findIndex(c => c.id === Number(id));
      if (idx !== -1) this.leadContacts.splice(idx, 1, data);
      return camelcaseKeys(data, { deep: true });
    },

    async deleteLeadContact(id) {
      await taskLeadContactsAPI.destroy(id);
      this.leadContacts = this.leadContacts.filter(c => c.id !== Number(id));
    },

    clearLeadContacts() {
      this.leadContacts = [];
    },

    // Stage automations (admin) ---------------------------------------
    async fetchAutomations(boardId, stageId) {
      const { data } = await taskStageAutomationsAPI.list(boardId, stageId);
      return camelcaseKeys(data, { deep: true });
    },

    async createAutomation(boardId, stageId, payload) {
      const { data } = await taskStageAutomationsAPI.create(
        boardId,
        stageId,
        payload
      );
      return camelcaseKeys(data, { deep: true });
    },

    async updateAutomation(boardId, stageId, id, payload) {
      const { data } = await taskStageAutomationsAPI.update(
        boardId,
        stageId,
        id,
        payload
      );
      return camelcaseKeys(data, { deep: true });
    },

    async deleteAutomation(boardId, stageId, id) {
      await taskStageAutomationsAPI.destroy(boardId, stageId, id);
    },
  },
});
