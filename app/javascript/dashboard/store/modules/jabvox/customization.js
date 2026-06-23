import api from '../../../api/jabvox/customization';

const state = {
  tables: [],
  buttons: [],
  uiFlags: {
    isFetchingTables: false,
    isFetchingButtons: false,
    isSaving: false,
  },
};

const getters = {
  getTables: s => s.tables,
  getButtons: s => s.buttons,
  getActiveButtons: s => s.buttons.filter(b => b.active_jabvox),
  getLeadsTable: s =>
    s.tables.find(t => t.linked_to_jabvox === 'leads') || null,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_UI_FLAGS(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
  SET_TABLES(s, tables) {
    s.tables = tables;
  },
  ADD_TABLE(s, table) {
    s.tables = [...s.tables, table];
  },
  UPDATE_TABLE(s, table) {
    s.tables = s.tables.map(t => (t.id === table.id ? table : t));
  },
  REMOVE_TABLE(s, id) {
    s.tables = s.tables.filter(t => t.id !== id);
  },
  SET_BUTTONS(s, buttons) {
    s.buttons = buttons;
  },
  ADD_BUTTON(s, button) {
    s.buttons = [...s.buttons, button];
  },
  UPDATE_BUTTON(s, button) {
    s.buttons = s.buttons.map(b => (b.id === button.id ? button : b));
  },
  REMOVE_BUTTON(s, id) {
    s.buttons = s.buttons.filter(b => b.id !== id);
  },
};

const actions = {
  async fetchTables({ commit }) {
    commit('SET_UI_FLAGS', { isFetchingTables: true });
    try {
      const { data } = await api.getTables();
      commit('SET_TABLES', data);
    } finally {
      commit('SET_UI_FLAGS', { isFetchingTables: false });
    }
  },

  async createTable({ commit }, tableData) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.createTable(tableData);
      commit('ADD_TABLE', data);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },

  async updateTable({ commit }, { id, ...tableData }) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.updateTable(id, tableData);
      commit('UPDATE_TABLE', data);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },

  async deleteTable({ commit }, id) {
    await api.deleteTable(id);
    commit('REMOVE_TABLE', id);
  },

  async createColumn({ commit, state: s }, { tableId, ...columnData }) {
    const { data } = await api.createColumn(tableId, columnData);
    const table = s.tables.find(t => t.id === tableId);
    if (table) {
      commit('UPDATE_TABLE', {
        ...table,
        columns: [...(table.columns || []), data],
      });
    }
    return data;
  },

  async updateColumn({ commit, state: s }, { tableId, id, ...columnData }) {
    const { data } = await api.updateColumn(tableId, id, columnData);
    const table = s.tables.find(t => t.id === tableId);
    if (table) {
      commit('UPDATE_TABLE', {
        ...table,
        columns: (table.columns || []).map(c => (c.id === id ? data : c)),
      });
    }
    return data;
  },

  async deleteColumn({ commit, state: s }, { tableId, id }) {
    await api.deleteColumn(tableId, id);
    const table = s.tables.find(t => t.id === tableId);
    if (table) {
      commit('UPDATE_TABLE', {
        ...table,
        columns: (table.columns || []).filter(c => c.id !== id),
      });
    }
  },

  async fetchButtons({ commit }) {
    commit('SET_UI_FLAGS', { isFetchingButtons: true });
    try {
      const { data } = await api.getButtons();
      commit('SET_BUTTONS', data);
    } finally {
      commit('SET_UI_FLAGS', { isFetchingButtons: false });
    }
  },

  async createButton({ commit }, buttonData) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.createButton(buttonData);
      commit('ADD_BUTTON', data);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },

  async updateButton({ commit }, { id, ...buttonData }) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.updateButton(id, buttonData);
      commit('UPDATE_BUTTON', data);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },

  async deleteButton({ commit }, id) {
    await api.deleteButton(id);
    commit('REMOVE_BUTTON', id);
  },

  async updateLeadCustomFields({ commit }, { leadId, customFields }) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.updateLeadCustomFields(leadId, customFields);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
