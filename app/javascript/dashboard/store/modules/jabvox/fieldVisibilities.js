import fieldVisibilitiesAPI from '../../../api/jabvox/fieldVisibilities';

const state = {
  userRows: [],
  myVisibilities: { phone: true, email: true, identification: true },
  uiFlags: { isFetching: false, isSaving: false },
};

const getters = {
  getUserRows: s => s.userRows,
  getMyVisibilities: s => s.myVisibilities,
  canView: s => field => s.myVisibilities[field] !== false,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
  SET_USER_ROWS(s, rows) {
    s.userRows = rows;
  },
  SET_MY_VISIBILITIES(s, vis) {
    s.myVisibilities = vis;
  },
  UPDATE_USER_FIELD(s, { userId, fieldName, canView }) {
    const user = s.userRows.find(u => u.id === userId);
    if (user) user.visibilities[fieldName] = canView;
  },
};

const actions = {
  async fetchAll({ commit }) {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await fieldVisibilitiesAPI.getAll();
      commit('SET_USER_ROWS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  async fetchMyVisibilities({ commit }) {
    try {
      const { data } = await fieldVisibilitiesAPI.getMe();
      commit('SET_MY_VISIBILITIES', data);
    } catch {
      // silently keep defaults
    }
  },
  async toggleField({ commit }, { userId, fieldName, canView }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      await fieldVisibilitiesAPI.update(userId, fieldName, canView);
      commit('UPDATE_USER_FIELD', { userId, fieldName, canView });
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
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
