import appStatesAPI from 'dashboard/api/jabvox/appStates';

const state = {
  states: [],
  currentUserAppStateId: null,
  uiFlags: { isFetching: false, isSaving: false },
};

const getters = {
  getStates: s => s.states,
  getActiveStates: s => s.states.filter(st => st.is_active),
  getCurrentUserAppStateId: s => s.currentUserAppStateId,
  getCurrentUserAppState: s =>
    s.states.find(st => st.id === s.currentUserAppStateId) || null,
  getUIFlags: s => s.uiFlags,
};

const actions = {
  fetchStates: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await appStatesAPI.getAll();
      commit('SET_STATES', data.states);
      commit('SET_CURRENT_APP_STATE', data.current_user_state_id || null);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  createState: async ({ commit }, params) => {
    const { data } = await appStatesAPI.create(params);
    commit('ADD_STATE', data);
    return data;
  },
  updateState: async ({ commit }, { id, ...params }) => {
    const { data } = await appStatesAPI.update(id, params);
    commit('UPDATE_STATE', data);
    return data;
  },
  deleteState: async ({ commit }, id) => {
    await appStatesAPI.destroy(id);
    commit('REMOVE_STATE', id);
  },
  setPresence: async ({ commit }, appStateId) => {
    await appStatesAPI.setPresence(appStateId);
    commit('SET_CURRENT_APP_STATE', appStateId || null);
  },
};

const mutations = {
  SET_STATES: (s, states) => {
    s.states = states;
  },
  ADD_STATE: (s, state) => {
    s.states = [...s.states, state];
  },
  UPDATE_STATE: (s, state) => {
    s.states = s.states.map(st => (st.id === state.id ? state : st));
  },
  REMOVE_STATE: (s, id) => {
    s.states = s.states.filter(st => st.id !== id);
  },
  SET_CURRENT_APP_STATE: (s, id) => {
    s.currentUserAppStateId = id;
  },
  SET_UI_FLAG: (s, flags) => {
    Object.assign(s.uiFlags, flags);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
