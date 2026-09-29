import api from '../../../api/jabvox/customization';

const state = {
  tables: [],
  buttons: [],
  // Los botones se piden una sola vez por sesión. Sin esta marca, una cuenta SIN botones
  // deja la lista vacía para siempre y cada tarjeta del kanban vuelve a pedirlos: seis
  // tarjetas visibles eran seis peticiones idénticas por render.
  buttonsLoaded: false,
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
  // La tabla de UNA fila por contacto: la que aporta sus campos personalizados.
  getLeadsTable: s =>
    s.tables.find(
      t => t.linked_to_jabvox === 'contacts' && t.kind_jabvox !== 'multi'
    ) || null,
  // Tablas de varias filas (Asesorías, Casos…) que se muestran en la ficha del contacto.
  getMultiTables: s => s.tables.filter(t => t.kind_jabvox === 'multi'),
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
    s.buttonsLoaded = true;
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

  // `force` para la pantalla de ajustes, que sí necesita releer tras guardar.
  async fetchButtons({ commit, state: s }, { force = false } = {}) {
    if (!force && (s.buttonsLoaded || s.uiFlags.isFetchingButtons)) return;

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

  // Standalone table rows (records). Kept component-local (no global state):
  // these actions are thin pass-throughs to the API so the data editor owns
  // its list for the currently-selected table.
  async fetchTableData(_ctx, tableId) {
    const { data } = await api.getTableData(tableId);
    return data;
  },

  async createRow({ commit }, { tableId, rowData }) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.createRow(tableId, rowData);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },

  async updateRow({ commit }, { tableId, rowId, rowData }) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.updateRow(tableId, rowId, rowData);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },

  async deleteRow(_ctx, { tableId, rowId }) {
    await api.deleteRow(tableId, rowId);
  },

  // Filas de las tablas de varias filas del contacto (Asesorías, Casos…). Los datos son
  // locales del componente (pertenecen al contacto abierto), así que son pasarelas finas.
  async fetchContactTableRows(_ctx, contactId) {
    const { data } = await api.getContactTableRows(contactId);
    return data;
  },

  async createContactTableRow({ commit }, { contactId, tableId, rowData }) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.createContactTableRow(
        contactId,
        tableId,
        rowData
      );
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },

  async updateContactTableRow(
    { commit },
    { contactId, tableId, rowId, rowData }
  ) {
    commit('SET_UI_FLAGS', { isSaving: true });
    try {
      const { data } = await api.updateContactTableRow(
        contactId,
        tableId,
        rowId,
        rowData
      );
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isSaving: false });
    }
  },

  async deleteContactTableRow(_ctx, { contactId, tableId, rowId }) {
    await api.deleteContactTableRow(contactId, tableId, rowId);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
