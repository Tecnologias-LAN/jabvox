import { campaignsAPI } from 'dashboard/api/jabvox/campaigns';

const state = {
  campaigns: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

const getters = {
  getCampaigns: s => s.campaigns,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_CAMPAIGNS(s, campaigns) {
    s.campaigns = campaigns;
  },
  REMOVE_CAMPAIGN(s, id) {
    s.campaigns = s.campaigns.filter(c => c.id !== id);
  },
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
};

const actions = {
  async fetchCampaigns({ commit }) {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await campaignsAPI.getAll();
      commit('SET_CAMPAIGNS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  async createCampaign({ commit, dispatch }, payload) {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      await campaignsAPI.create(payload);
      await dispatch('fetchCampaigns');
    } catch (error) {
      throw new Error(error?.response?.data?.error || error.message);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  async updateCampaign({ commit, dispatch }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      await campaignsAPI.update(id, payload);
      await dispatch('fetchCampaigns');
    } catch (error) {
      throw new Error(error?.response?.data?.error || error.message);
    } finally {
      commit('SET_UI_FLAG', { isUpdating: false });
    }
  },

  async deleteCampaign({ commit }, id) {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await campaignsAPI.destroy(id);
      commit('REMOVE_CAMPAIGN', id);
    } catch (error) {
      throw new Error(error?.response?.data?.error || error.message);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },
};

export default { namespaced: true, state, getters, mutations, actions };
