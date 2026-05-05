import {
  dialerCampaignsAPI,
  dialerCallLogsAPI,
  dialerStatesAPI,
  dialerAccessesAPI,
} from 'dashboard/api/jabvox/dialer';

const state = {
  campaigns: [],
  activeCampaign: null,
  contacts: [],
  callLogs: [],
  dialerStates: [],
  dialerAccesses: [],
  uiFlags: {
    isFetchingCampaigns: false,
    isFetchingContacts: false,
    isFetchingLogs: false,
    isSaving: false,
    isImporting: false,
    isOriginating: false,
    isFetchingStates: false,
    isSavingState: false,
    isFetchingAccesses: false,
  },
};

const getters = {
  getCampaigns: s => s.campaigns,
  getActiveCampaign: s => s.activeCampaign,
  getContacts: s => s.contacts,
  getCallLogs: s => s.callLogs,
  getDialerStates: s => s.dialerStates,
  getDialerAccesses: s => s.dialerAccesses,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_CAMPAIGNS(s, v) {
    s.campaigns = v;
  },
  SET_ACTIVE_CAMPAIGN(s, v) {
    s.activeCampaign = v;
  },
  ADD_CAMPAIGN(s, v) {
    s.campaigns = [v, ...s.campaigns];
  },
  UPDATE_CAMPAIGN(s, v) {
    s.campaigns = s.campaigns.map(c => (c.id === v.id ? v : c));
    if (s.activeCampaign?.id === v.id) s.activeCampaign = v;
  },
  REMOVE_CAMPAIGN(s, id) {
    s.campaigns = s.campaigns.filter(c => c.id !== id);
    if (s.activeCampaign?.id === id) s.activeCampaign = null;
  },
  SET_CONTACTS(s, v) {
    s.contacts = v;
  },
  SET_CALL_LOGS(s, v) {
    s.callLogs = v;
  },
  SET_DIALER_STATES(s, v) {
    s.dialerStates = v;
  },
  ADD_DIALER_STATE(s, v) {
    s.dialerStates = [...s.dialerStates, v];
  },
  UPDATE_DIALER_STATE(s, v) {
    s.dialerStates = s.dialerStates.map(st => (st.id === v.id ? v : st));
  },
  REMOVE_DIALER_STATE(s, id) {
    s.dialerStates = s.dialerStates.filter(st => st.id !== id);
  },
  SET_DIALER_ACCESSES(s, v) {
    s.dialerAccesses = v;
  },
  UPSERT_DIALER_ACCESS(s, v) {
    const idx = s.dialerAccesses.findIndex(a => a.user_id === v.user_id);
    if (idx !== -1) s.dialerAccesses.splice(idx, 1, v);
    else s.dialerAccesses.push(v);
  },
  SET_UI_FLAG(s, f) {
    s.uiFlags = { ...s.uiFlags, ...f };
  },
};

const actions = {
  async fetchCampaigns({ commit }) {
    commit('SET_UI_FLAG', { isFetchingCampaigns: true });
    try {
      const { data } = await dialerCampaignsAPI.getAll();
      commit('SET_CAMPAIGNS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingCampaigns: false });
    }
  },

  async createCampaign({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await dialerCampaignsAPI.create(payload);
      commit('ADD_CAMPAIGN', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async updateCampaign({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await dialerCampaignsAPI.update(id, payload);
      commit('UPDATE_CAMPAIGN', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async deleteCampaign({ commit }, id) {
    await dialerCampaignsAPI.destroy(id);
    commit('REMOVE_CAMPAIGN', id);
  },

  async startCampaign({ commit }, id) {
    const { data } = await dialerCampaignsAPI.start(id);
    commit('UPDATE_CAMPAIGN', data);
    return data;
  },

  async pauseCampaign({ commit }, id) {
    const { data } = await dialerCampaignsAPI.pause(id);
    commit('UPDATE_CAMPAIGN', data);
    return data;
  },

  async stopCampaign({ commit }, id) {
    const { data } = await dialerCampaignsAPI.stop(id);
    commit('UPDATE_CAMPAIGN', data);
    return data;
  },

  async fetchContacts({ commit }, campaignId) {
    commit('SET_UI_FLAG', { isFetchingContacts: true });
    try {
      const { data } = await dialerCampaignsAPI.getContacts(campaignId);
      commit('SET_CONTACTS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingContacts: false });
    }
  },

  async fetchCallLogs({ commit }, campaignId) {
    commit('SET_UI_FLAG', { isFetchingLogs: true });
    try {
      const { data } = await dialerCampaignsAPI.getCallLogs(campaignId);
      commit('SET_CALL_LOGS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingLogs: false });
    }
  },

  async importContacts({ commit, dispatch }, { campaignId, contacts }) {
    commit('SET_UI_FLAG', { isImporting: true });
    try {
      const { data } = await dialerCampaignsAPI.importContacts(
        campaignId,
        contacts
      );
      await dispatch('fetchContacts', campaignId);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isImporting: false });
    }
  },

  async originate({ commit }, { campaignId, contactId, extension }) {
    commit('SET_UI_FLAG', { isOriginating: true });
    try {
      const { data } = await dialerCampaignsAPI.originate(campaignId, {
        contact_id: contactId,
        extension,
      });
      return data;
    } finally {
      commit('SET_UI_FLAG', { isOriginating: false });
    }
  },

  async fetchAllCallLogs({ commit }) {
    commit('SET_UI_FLAG', { isFetchingLogs: true });
    try {
      const { data } = await dialerCallLogsAPI.getAll();
      commit('SET_CALL_LOGS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingLogs: false });
    }
  },

  async fetchDialerStates({ commit }) {
    commit('SET_UI_FLAG', { isFetchingStates: true });
    try {
      const { data } = await dialerStatesAPI.getAll();
      commit('SET_DIALER_STATES', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingStates: false });
    }
  },

  async createDialerState({ commit }, payload) {
    commit('SET_UI_FLAG', { isSavingState: true });
    try {
      const { data } = await dialerStatesAPI.create(payload);
      commit('ADD_DIALER_STATE', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSavingState: false });
    }
  },

  async updateDialerState({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSavingState: true });
    try {
      const { data } = await dialerStatesAPI.update(id, payload);
      commit('UPDATE_DIALER_STATE', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSavingState: false });
    }
  },

  async deleteDialerState({ commit }, id) {
    await dialerStatesAPI.destroy(id);
    commit('REMOVE_DIALER_STATE', id);
  },

  async fetchDialerAccesses({ commit }) {
    commit('SET_UI_FLAG', { isFetchingAccesses: true });
    try {
      const { data } = await dialerAccessesAPI.getAll();
      commit('SET_DIALER_ACCESSES', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingAccesses: false });
    }
  },

  async updateDialerAccess({ commit }, { userId, canAccess }) {
    const { data } = await dialerAccessesAPI.update(userId, canAccess);
    commit('UPSERT_DIALER_ACCESS', data);
  },
};

export default { namespaced: true, state, getters, mutations, actions };
