import { managementStatesAPI } from 'dashboard/api/jabvox/managementStates';

const state = {
  states: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

const getters = {
  getStates: s => s.states,
  getActiveStates: s => s.states.filter(st => st.is_active_jabvox),
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_STATES(s, states) {
    s.states = states;
  },
  ADD_STATE(s, record) {
    s.states.push(record);
  },
  UPDATE_STATE(s, updated) {
    const idx = s.states.findIndex(st => st.id === updated.id);
    if (idx !== -1) s.states.splice(idx, 1, updated);
  },
  REMOVE_STATE(s, id) {
    s.states = s.states.filter(st => st.id !== id);
  },
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
};

const actions = {
  async fetchStates({ commit }) {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await managementStatesAPI.getAll();
      commit('SET_STATES', data);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  async createState({ commit, dispatch }, payload) {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const { data } = await managementStatesAPI.create(payload);
      await dispatch('fetchStates');
      return data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  async updateState({ commit, dispatch }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      const { data } = await managementStatesAPI.update(id, payload);
      await dispatch('fetchStates');
      return data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isUpdating: false });
    }
  },

  async deleteState({ commit }, id) {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await managementStatesAPI.destroy(id);
      commit('REMOVE_STATE', id);
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },
};

export default { namespaced: true, state, getters, mutations, actions };
