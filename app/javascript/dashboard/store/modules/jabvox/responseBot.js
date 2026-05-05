import {
  responseBotSeatsAPI,
  responseBotConfigsAPI,
  responseBotDocumentsAPI,
} from 'dashboard/api/jabvox/responseBot';
import { aiChatModelsAPI } from 'dashboard/api/jabvox/aiChat';

const state = {
  seats: [],
  configs: [],
  documents: [],
  aiModels: [],
  uiFlags: {
    isFetchingSeats: false,
    isFetchingConfigs: false,
    isFetchingDocuments: false,
    isFetchingModels: false,
    isSaving: false,
    isSyncing: false,
  },
};

const getters = {
  getSeats($state) {
    return $state.seats;
  },
  getConfigs($state) {
    return $state.configs;
  },
  getDocuments($state) {
    return $state.documents;
  },
  getAiModels($state) {
    return $state.aiModels;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

const mutations = {
  SET_SEATS($state, seats) {
    $state.seats = seats;
  },
  SET_CONFIGS($state, configs) {
    $state.configs = configs;
  },
  ADD_CONFIG($state, config) {
    $state.configs.push(config);
  },
  UPDATE_CONFIG($state, config) {
    const idx = $state.configs.findIndex(c => c.id === config.id);
    if (idx !== -1) $state.configs.splice(idx, 1, config);
  },
  REMOVE_CONFIG($state, id) {
    $state.configs = $state.configs.filter(c => c.id !== id);
  },
  SET_DOCUMENTS($state, documents) {
    $state.documents = documents;
  },
  UPDATE_DOCUMENT($state, doc) {
    const idx = $state.documents.findIndex(d => d.id === doc.id);
    if (idx !== -1) $state.documents.splice(idx, 1, doc);
  },
  REMOVE_DOCUMENT($state, id) {
    $state.documents = $state.documents.filter(d => d.id !== id);
  },
  SET_AI_MODELS($state, models) {
    $state.aiModels = models;
  },
  SET_UI_FLAG($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
};

const actions = {
  async fetchSeats({ commit }) {
    commit('SET_UI_FLAG', { isFetchingSeats: true });
    try {
      const { data } = await responseBotSeatsAPI.getAll();
      commit('SET_SEATS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingSeats: false });
    }
  },

  async fetchConfigs({ commit }) {
    commit('SET_UI_FLAG', { isFetchingConfigs: true });
    try {
      const { data } = await responseBotConfigsAPI.getAll();
      commit('SET_CONFIGS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingConfigs: false });
    }
  },

  async createConfig({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await responseBotConfigsAPI.create(payload);
      commit('ADD_CONFIG', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async updateConfig({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await responseBotConfigsAPI.update(id, payload);
      commit('UPDATE_CONFIG', data);
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async destroyConfig({ commit }, id) {
    await responseBotConfigsAPI.destroy(id);
    commit('REMOVE_CONFIG', id);
  },

  async setupLabels() {
    await responseBotConfigsAPI.setupLabels();
  },

  async fetchAiModels({ commit }) {
    commit('SET_UI_FLAG', { isFetchingModels: true });
    try {
      const { data } = await aiChatModelsAPI.getAll();
      commit('SET_AI_MODELS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingModels: false });
    }
  },

  async fetchDocuments({ commit }) {
    commit('SET_UI_FLAG', { isFetchingDocuments: true });
    try {
      const { data } = await responseBotDocumentsAPI.getAll();
      commit('SET_DOCUMENTS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingDocuments: false });
    }
  },

  async syncDocuments({ commit }) {
    commit('SET_UI_FLAG', { isSyncing: true });
    try {
      const { data } = await responseBotDocumentsAPI.sync();
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSyncing: false });
    }
  },

  async updateDocument({ commit }, { id, ...payload }) {
    const { data } = await responseBotDocumentsAPI.update(id, payload);
    commit('UPDATE_DOCUMENT', data);
  },

  async deleteDocument({ commit }, id) {
    await responseBotDocumentsAPI.destroy(id);
    commit('REMOVE_DOCUMENT', id);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
