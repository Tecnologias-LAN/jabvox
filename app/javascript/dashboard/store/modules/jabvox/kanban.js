import kanbanAPI from '../../../api/jabvox/kanban';

const normalizeFunnelsPayload = data => {
  if (Array.isArray(data?.payload)) return data.payload;
  if (Array.isArray(data)) return data;
  return [];
};

const normalizeFunnelPayload = data => {
  if (data?.payload && !Array.isArray(data.payload)) return data.payload;
  return data;
};

const state = {
  funnels: [],
  currentBoard: null,
  uiFlags: {
    isFetchingFunnels: false,
    isFetchingBoard: false,
    isCreatingFunnel: false,
    isUpdatingFunnel: false,
    isDeletingFunnel: false,
    isCreatingStage: false,
    isUpdatingStage: false,
    isDeletingStage: false,
    isMovingConversation: false,
  },
};

export const getters = {
  getFunnels: _state => _state.funnels,
  getCurrentBoard: _state => _state.currentBoard,
  getUIFlags: _state => _state.uiFlags,
  getFunnelById: _state => id => _state.funnels.find(f => f.id === id),
};

export const actions = {
  fetchFunnels: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetchingFunnels: true });
    try {
      const response = await kanbanAPI.getAll();
      commit('SET_FUNNELS', normalizeFunnelsPayload(response.data));
    } catch {
      // ignore
    } finally {
      commit('SET_UI_FLAG', { isFetchingFunnels: false });
    }
  },

  fetchBoard: async ({ commit }, funnelId) => {
    commit('SET_UI_FLAG', { isFetchingBoard: true });
    try {
      const response = await kanbanAPI.getBoard(funnelId);
      commit('SET_BOARD', response.data);
    } catch {
      // ignore
    } finally {
      commit('SET_UI_FLAG', { isFetchingBoard: false });
    }
  },

  createFunnel: async ({ commit }, data) => {
    commit('SET_UI_FLAG', { isCreatingFunnel: true });
    try {
      const response = await kanbanAPI.create(data);
      const funnel = normalizeFunnelPayload(response.data);
      commit('ADD_FUNNEL', funnel);
      return funnel;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isCreatingFunnel: false });
    }
  },

  updateFunnel: async ({ commit }, { id, ...data }) => {
    commit('SET_UI_FLAG', { isUpdatingFunnel: true });
    try {
      const response = await kanbanAPI.update(id, data);
      const funnel = normalizeFunnelPayload(response.data);
      commit('UPDATE_FUNNEL', funnel);
      return funnel;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isUpdatingFunnel: false });
    }
  },

  deleteFunnel: async ({ commit }, id) => {
    commit('SET_UI_FLAG', { isDeletingFunnel: true });
    try {
      await kanbanAPI.destroy(id);
      commit('REMOVE_FUNNEL', id);
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isDeletingFunnel: false });
    }
  },

  createStage: async ({ commit }, { funnelId, ...data }) => {
    commit('SET_UI_FLAG', { isCreatingStage: true });
    try {
      const response = await kanbanAPI.createStage(funnelId, { stage: data });
      commit('ADD_STAGE_TO_FUNNEL', { funnelId, stage: response.data });
      return response.data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isCreatingStage: false });
    }
  },

  updateStage: async ({ commit }, { funnelId, stageId, ...data }) => {
    commit('SET_UI_FLAG', { isUpdatingStage: true });
    try {
      const response = await kanbanAPI.updateStage(funnelId, stageId, {
        stage: data,
      });
      commit('UPDATE_STAGE_IN_FUNNEL', { funnelId, stage: response.data });
      return response.data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isUpdatingStage: false });
    }
  },

  deleteStage: async ({ commit }, { funnelId, stageId }) => {
    commit('SET_UI_FLAG', { isDeletingStage: true });
    try {
      await kanbanAPI.deleteStage(funnelId, stageId);
      commit('REMOVE_STAGE_FROM_FUNNEL', { funnelId, stageId });
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isDeletingStage: false });
    }
  },

  moveConversation: async (
    { commit },
    { funnelId, conversationId, stageId }
  ) => {
    commit('SET_UI_FLAG', { isMovingConversation: true });
    try {
      await kanbanAPI.moveConversation(funnelId, conversationId, stageId);
      commit('MOVE_CONVERSATION_IN_BOARD', { conversationId, stageId });
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isMovingConversation: false });
    }
  },
};

export const mutations = {
  SET_UI_FLAG(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },

  SET_FUNNELS(_state, funnels) {
    _state.funnels = funnels;
  },

  SET_BOARD(_state, board) {
    _state.currentBoard = board;
  },

  ADD_FUNNEL(_state, funnel) {
    _state.funnels.push(funnel);
  },

  UPDATE_FUNNEL(_state, updatedFunnel) {
    const idx = _state.funnels.findIndex(f => f.id === updatedFunnel.id);
    if (idx !== -1) _state.funnels.splice(idx, 1, updatedFunnel);
  },

  REMOVE_FUNNEL(_state, id) {
    _state.funnels = _state.funnels.filter(f => f.id !== id);
  },

  ADD_STAGE_TO_FUNNEL(_state, { funnelId, stage }) {
    const funnel = _state.funnels.find(f => f.id === funnelId);
    if (funnel) funnel.stages = [...(funnel.stages || []), stage];
  },

  UPDATE_STAGE_IN_FUNNEL(_state, { funnelId, stage }) {
    const funnel = _state.funnels.find(f => f.id === funnelId);
    if (!funnel) return;
    const idx = funnel.stages.findIndex(s => s.id === stage.id);
    if (idx !== -1) funnel.stages.splice(idx, 1, stage);
  },

  REMOVE_STAGE_FROM_FUNNEL(_state, { funnelId, stageId }) {
    const funnel = _state.funnels.find(f => f.id === funnelId);
    if (funnel) funnel.stages = funnel.stages.filter(s => s.id !== stageId);
  },

  MOVE_CONVERSATION_IN_BOARD(_state, { conversationId, stageId }) {
    if (!_state.currentBoard) return;
    let conversation = null;
    _state.currentBoard.stages.forEach(s => {
      const idx = s.conversations.findIndex(c => c.id === conversationId);
      if (idx !== -1) {
        [conversation] = s.conversations.splice(idx, 1);
      }
    });
    if (!conversation) return;
    const targetStage = _state.currentBoard.stages.find(s => s.id === stageId);
    if (targetStage) targetStage.conversations.push(conversation);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
