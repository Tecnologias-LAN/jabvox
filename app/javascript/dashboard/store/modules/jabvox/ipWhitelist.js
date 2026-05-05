import { ipWhitelistAPI } from 'dashboard/api/jabvox/ipWhitelist';
import { clearCookiesOnLogout } from 'dashboard/store/utils/api';

const state = {
  entries: [],
  uiFlags: { isFetching: false, isSaving: false },
};

const getters = {
  getEntries: s => s.entries,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_ENTRIES(s, entries) {
    s.entries = entries;
  },
  ADD_ENTRY(s, entry) {
    s.entries = [...s.entries, entry];
  },
  UPDATE_ENTRY(s, updated) {
    s.entries = s.entries.map(e => (e.id === updated.id ? updated : e));
  },
  REMOVE_ENTRY(s, id) {
    s.entries = s.entries.filter(e => e.id !== id);
  },
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
};

function logoutIfBlocked(data) {
  if (data?.requester_blocked) {
    clearCookiesOnLogout();
    window.location.href = '/app/login';
    return true;
  }
  return false;
}

const actions = {
  async fetchEntries({ commit }) {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await ipWhitelistAPI.getAll();
      commit('SET_ENTRIES', data);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  async createEntry({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await ipWhitelistAPI.create(payload);
      if (logoutIfBlocked(data)) return null;
      commit('ADD_ENTRY', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async updateEntry({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await ipWhitelistAPI.update(id, payload);
      if (logoutIfBlocked(data)) return null;
      commit('UPDATE_ENTRY', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async deleteEntry({ commit }, id) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await ipWhitelistAPI.destroy(id);
      if (logoutIfBlocked(data)) return;
      commit('REMOVE_ENTRY', id);
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },
};

export default { namespaced: true, state, getters, mutations, actions };
