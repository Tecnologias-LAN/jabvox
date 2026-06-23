import { defineStore } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import {
  tasksBoardsAPI,
  tasksAPI,
  taskLeadContactsAPI,
  taskStageAutomationsAPI,
} from 'dashboard/api/jabvox/tasks';

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
      Object.keys(grouped).forEach(key => {
        grouped[key].sort((a, b) => a.positionJabvox - b.positionJabvox);
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

    async deleteBoard(id) {
      await tasksBoardsAPI.destroy(id);
      this.boards = this.boards.filter(b => b.id !== Number(id));
    },

    // Stages -----------------------------------------------------------
    async createStage(boardId, payload) {
      const { data } = await tasksBoardsAPI.createStage(boardId, payload);
      if (this.currentBoard && this.currentBoard.id === Number(boardId)) {
        const stages = this.currentBoard.stages || [];
        this.currentBoard = {
          ...this.currentBoard,
          stages: [...stages, data],
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
        this.currentBoard = { ...this.currentBoard, stages };
      }
      return camelcaseKeys(data, { deep: true });
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
      const idx = this.tasks.findIndex(tk => tk.id === Number(id));
      // Optimistic update so the card lands immediately.
      if (idx !== -1) {
        this.tasks.splice(idx, 1, {
          ...this.tasks[idx],
          stage_id: stageId,
          position_jabvox: position,
        });
      }
      const { data } = await tasksAPI.move(id, stageId, position);
      const after = this.tasks.findIndex(tk => tk.id === Number(id));
      if (after !== -1) this.tasks.splice(after, 1, data);
      return camelcaseKeys(data, { deep: true });
    },

    async deleteTask(id) {
      await tasksAPI.destroy(id);
      this.tasks = this.tasks.filter(tk => tk.id !== Number(id));
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
