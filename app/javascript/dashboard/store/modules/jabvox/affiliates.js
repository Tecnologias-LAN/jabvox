import affiliatesAPI from '../../../api/jabvox/affiliates';

const state = {
  affiliates: [],
  portalLoginUrl: '',
  uiFlags: { isFetching: false, isSaving: false },
};

const getters = {
  getAffiliates: s => s.affiliates,
  getPortalLoginUrl: s => s.portalLoginUrl,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_AFFILIATES(s, affiliates) {
    s.affiliates = affiliates;
  },
  SET_PORTAL_URL(s, url) {
    s.portalLoginUrl = url;
  },
  ADD_AFFILIATE(s, affiliate) {
    s.affiliates.unshift(affiliate);
  },
  UPDATE_AFFILIATE(s, affiliate) {
    const idx = s.affiliates.findIndex(a => a.id === affiliate.id);
    if (idx !== -1) s.affiliates.splice(idx, 1, affiliate);
  },
  REMOVE_AFFILIATE(s, id) {
    s.affiliates = s.affiliates.filter(a => a.id !== id);
  },
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
};

const actions = {
  async fetchAffiliates({ commit }) {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await affiliatesAPI.getAll();
      commit('SET_AFFILIATES', data);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  async fetchPortalLoginUrl({ commit }) {
    const { data } = await affiliatesAPI.getPortalLoginUrl();
    commit('SET_PORTAL_URL', data.url);
  },

  async createAffiliate({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await affiliatesAPI.create(payload);
      commit('ADD_AFFILIATE', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async updateAffiliate({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await affiliatesAPI.update(id, payload);
      commit('UPDATE_AFFILIATE', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async deleteAffiliate({ commit }, id) {
    await affiliatesAPI.destroy(id);
    commit('REMOVE_AFFILIATE', id);
  },

  async regenerateToken({ commit }, id) {
    const { data } = await affiliatesAPI.regenerateToken(id);
    commit('UPDATE_AFFILIATE', data);
    return data;
  },

  async regenerateCode({ commit }, id) {
    const { data } = await affiliatesAPI.regenerateCode(id);
    commit('UPDATE_AFFILIATE', data);
    return data;
  },
};

export default { namespaced: true, state, getters, mutations, actions };
