import leadsAPI from '../../../api/jabvox/leads';

const state = {
  leads: [],
  currentLead: null,
  filterOptions: {
    management_states: [],
    campaigns: [],
    inboxes: [],
    teams: [],
    assignees: [],
  },
  meta: { total: 0, currentPage: 1, totalPages: 1 },
  uiFlags: { isFetching: false, isFetchingOne: false },
};

const getters = {
  getLeads: s => s.leads,
  getCurrentLead: s => s.currentLead,
  getFilterOptions: s => s.filterOptions,
  getMeta: s => s.meta,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_UI_FLAGS(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
  SET_LEADS(s, leads) {
    s.leads = leads;
  },
  SET_CURRENT_LEAD(s, lead) {
    s.currentLead = lead;
  },
  SET_FILTER_OPTIONS(s, opts) {
    s.filterOptions = opts;
  },
  SET_META(s, meta) {
    s.meta = meta;
  },
};

const actions = {
  async fetchLeads({ commit }, params = {}) {
    commit('SET_UI_FLAGS', { isFetching: true });
    try {
      const { data } = await leadsAPI.getAll(params);
      commit('SET_LEADS', data.data);
      commit('SET_META', data.meta);
      if (data.filter_options)
        commit('SET_FILTER_OPTIONS', data.filter_options);
    } finally {
      commit('SET_UI_FLAGS', { isFetching: false });
    }
  },
  async fetchLead({ commit }, id) {
    commit('SET_UI_FLAGS', { isFetchingOne: true });
    try {
      const { data } = await leadsAPI.getById(id);
      commit('SET_CURRENT_LEAD', data);
    } finally {
      commit('SET_UI_FLAGS', { isFetchingOne: false });
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
