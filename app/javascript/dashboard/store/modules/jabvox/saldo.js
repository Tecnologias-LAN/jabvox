import { saldoAPI } from 'dashboard/api/jabvox/saldo';

const state = {
  config: null,
  status: null,
  uiFlags: { isFetching: false, isSaving: false, isCheckingStatus: false },
};

const getters = {
  getConfig: s => s.config,
  getStatus: s => s.status,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_CONFIG(s, config) {
    s.config = config;
  },
  SET_STATUS(s, status) {
    s.status = status;
  },
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
};

const actions = {
  async fetchConfig({ commit }) {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await saldoAPI.get();
      commit('SET_CONFIG', data);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  async updateConfig({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await saldoAPI.update(payload);
      commit('SET_CONFIG', data);
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async fetchStatus({ commit }) {
    commit('SET_UI_FLAG', { isCheckingStatus: true });
    try {
      const { data } = await saldoAPI.status();
      commit('SET_STATUS', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isCheckingStatus: false });
    }
  },
};

export default { namespaced: true, state, getters, mutations, actions };
