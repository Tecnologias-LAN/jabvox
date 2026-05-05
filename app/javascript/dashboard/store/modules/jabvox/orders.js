import ordersAPI from '../../../api/jabvox/orders';

const state = {
  orders: [],
  uiFlags: {
    isFetching: false,
    isSaving: false,
    isSendingToAlegra: false,
  },
};

const getters = {
  getOrders: s => s.orders,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
  SET_ORDERS(s, orders) {
    s.orders = orders;
  },
  ADD_ORDER(s, order) {
    s.orders.unshift(order);
  },
  REMOVE_ORDER(s, id) {
    s.orders = s.orders.filter(o => o.id !== id);
  },
  UPDATE_ORDER(s, order) {
    const idx = s.orders.findIndex(o => o.id === order.id);
    if (idx !== -1) s.orders.splice(idx, 1, order);
  },
};

const actions = {
  async fetchOrders({ commit }, params = {}) {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await ordersAPI.getAll(params);
      commit('SET_ORDERS', Array.isArray(data) ? data : []);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  async createOrder({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await ordersAPI.create({ order: payload });
      commit('ADD_ORDER', data);
      return data;
    } catch (error) {
      throw new Error(error?.response?.data?.error || error.message);
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },
  async destroyOrder({ commit }, id) {
    try {
      await ordersAPI.destroy(id);
      commit('REMOVE_ORDER', id);
    } catch (error) {
      throw new Error(error?.response?.data?.error || error.message);
    }
  },
  async updateOrderStatus({ commit }, { id, status }) {
    try {
      const { data } = await ordersAPI.update(id, { order: { status } });
      commit('UPDATE_ORDER', data);
      return data;
    } catch (error) {
      throw new Error(error?.response?.data?.error || error.message);
    }
  },
  async sendOrderToAlegra({ commit }, id) {
    commit('SET_UI_FLAG', { isSendingToAlegra: true });
    try {
      const { data } = await ordersAPI.sendToAlegra(id);
      commit('UPDATE_ORDER', data);
      return data;
    } catch (error) {
      throw new Error(error?.response?.data?.error || error.message);
    } finally {
      commit('SET_UI_FLAG', { isSendingToAlegra: false });
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
