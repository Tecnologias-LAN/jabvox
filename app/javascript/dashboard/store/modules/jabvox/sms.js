import {
  smsProvidersAPI,
  smsCampaignsAPI,
  smsMessagesAPI,
} from 'dashboard/api/jabvox/sms';

const state = {
  providers: [],
  campaigns: [],
  messages: [],
  contacts: [],
  stats: null,
  messagesMeta: { total: 0, currentPage: 1, totalPages: 1 },
  uiFlags: {
    isFetchingProviders: false,
    isFetchingCampaigns: false,
    isFetchingMessages: false,
    isFetchingContacts: false,
    isSaving: false,
    isSending: false,
  },
};

const getters = {
  getProviders: s => s.providers,
  getCampaigns: s => s.campaigns,
  getMessages: s => s.messages,
  getContacts: s => s.contacts,
  getStats: s => s.stats,
  getMessagesMeta: s => s.messagesMeta,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_PROVIDERS(s, v) {
    s.providers = v;
  },
  SET_CAMPAIGNS(s, v) {
    s.campaigns = v;
  },
  SET_MESSAGES(s, v) {
    s.messages = v;
  },
  SET_CONTACTS(s, v) {
    s.contacts = v;
  },
  SET_STATS(s, v) {
    s.stats = v;
  },
  SET_MESSAGES_META(s, v) {
    s.messagesMeta = v;
  },
  SET_UI_FLAG(s, f) {
    s.uiFlags = { ...s.uiFlags, ...f };
  },
  ADD_PROVIDER(s, v) {
    s.providers = [v, ...s.providers];
  },
  UPDATE_PROVIDER(s, v) {
    s.providers = s.providers.map(p => (p.id === v.id ? v : p));
  },
  REMOVE_PROVIDER(s, id) {
    s.providers = s.providers.filter(p => p.id !== id);
  },
  ADD_CAMPAIGN(s, v) {
    s.campaigns = [v, ...s.campaigns];
  },
  UPDATE_CAMPAIGN(s, v) {
    s.campaigns = s.campaigns.map(c => (c.id === v.id ? v : c));
  },
  REMOVE_CAMPAIGN(s, id) {
    s.campaigns = s.campaigns.filter(c => c.id !== id);
  },
};

const actions = {
  async fetchProviders({ commit }) {
    commit('SET_UI_FLAG', { isFetchingProviders: true });
    try {
      const { data } = await smsProvidersAPI.getAll();
      commit('SET_PROVIDERS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingProviders: false });
    }
  },

  async createProvider({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await smsProvidersAPI.create(payload);
      commit('ADD_PROVIDER', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async updateProvider({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await smsProvidersAPI.update(id, payload);
      commit('UPDATE_PROVIDER', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async deleteProvider({ commit }, id) {
    await smsProvidersAPI.destroy(id);
    commit('REMOVE_PROVIDER', id);
  },

  async fetchCampaigns({ commit }) {
    commit('SET_UI_FLAG', { isFetchingCampaigns: true });
    try {
      const { data } = await smsCampaignsAPI.getAll();
      commit('SET_CAMPAIGNS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingCampaigns: false });
    }
  },

  async createCampaign({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await smsCampaignsAPI.create(payload);
      commit('ADD_CAMPAIGN', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async updateCampaign({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await smsCampaignsAPI.update(id, payload);
      commit('UPDATE_CAMPAIGN', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async deleteCampaign({ commit }, id) {
    await smsCampaignsAPI.destroy(id);
    commit('REMOVE_CAMPAIGN', id);
  },

  async sendBulk({ commit, dispatch }, id) {
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const { data } = await smsCampaignsAPI.sendBulk(id);
      await dispatch('fetchCampaigns');
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  async fetchContacts({ commit }) {
    commit('SET_UI_FLAG', { isFetchingContacts: true });
    try {
      const { data } = await smsCampaignsAPI.getContacts();
      commit('SET_CONTACTS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingContacts: false });
    }
  },

  async fetchMessages({ commit }, params = {}) {
    commit('SET_UI_FLAG', { isFetchingMessages: true });
    try {
      const { data } = await smsMessagesAPI.getAll(params);
      commit('SET_MESSAGES', data.data);
      commit('SET_MESSAGES_META', data.meta);
    } finally {
      commit('SET_UI_FLAG', { isFetchingMessages: false });
    }
  },

  async fetchStats({ commit }) {
    const { data } = await smsMessagesAPI.getStats();
    commit('SET_STATS', data);
  },
};

export default { namespaced: true, state, getters, mutations, actions };
