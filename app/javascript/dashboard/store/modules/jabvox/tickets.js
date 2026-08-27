import ticketsAPI from '../../../api/jabvox/tickets';

const state = {
  records: [],
  currentTicket: null,
  comments: [],
  categories: [],
  metrics: null,
  permissions: {
    staff: false,
    resolver: false,
    manager: false,
    resolver_sees_all: false,
  },
  notificationPreferences: { in_app: true, email: true },
  counts: { today: 0, overdue_previous: 0, total_pending: 0 },
  meta: { total: 0, currentPage: 1, totalPages: 1 },
  uiFlags: {
    isFetching: false,
    isFetchingOne: false,
    isCreating: false,
    isUpdating: false,
  },
};

const getters = {
  getTickets: s => s.records,
  getCurrentTicket: s => s.currentTicket,
  getComments: s => s.comments,
  getCategories: s => s.categories,
  getMetrics: s => s.metrics,
  getMeta: s => s.meta,
  getUIFlags: s => s.uiFlags,
  getPermissions: s => s.permissions,
  isStaff: s => s.permissions.staff,
  canResolve: s => s.permissions.resolver,
  isManager: s => s.permissions.manager,
  resolverSeesAll: s => s.permissions.resolver_sees_all,
  getNotificationPreferences: s => s.notificationPreferences,
  getCounts: s => s.counts,
};

const mutations = {
  SET_UI_FLAGS(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
  SET_TICKETS(s, records) {
    s.records = records;
  },
  SET_CURRENT_TICKET(s, ticket) {
    s.currentTicket = ticket;
  },
  SET_COMMENTS(s, comments) {
    s.comments = comments;
  },
  ADD_COMMENT(s, comment) {
    s.comments = [...s.comments, comment];
  },
  SET_CATEGORIES(s, categories) {
    s.categories = categories;
  },
  SET_METRICS(s, metrics) {
    s.metrics = metrics;
  },
  SET_PERMISSIONS(s, permissions) {
    s.permissions = { ...s.permissions, ...permissions };
  },
  SET_META(s, meta) {
    const m = meta || {};
    s.meta = {
      total: m.total ?? 0,
      currentPage: m.current_page ?? 1,
      totalPages: m.total_pages ?? 1,
    };
  },
  SET_NOTIFICATION_PREFERENCES(s, prefs) {
    s.notificationPreferences = { ...s.notificationPreferences, ...prefs };
  },
  SET_COUNTS(s, counts) {
    s.counts = { ...s.counts, ...counts };
  },
};

const actions = {
  async fetchTickets({ commit }, params = {}) {
    commit('SET_UI_FLAGS', { isFetching: true });
    try {
      const { data } = await ticketsAPI.getAll(params);
      commit('SET_TICKETS', data.data);
      commit('SET_META', data.meta);
    } finally {
      commit('SET_UI_FLAGS', { isFetching: false });
    }
  },
  async fetchTicket({ commit }, id) {
    commit('SET_UI_FLAGS', { isFetchingOne: true });
    try {
      const { data } = await ticketsAPI.getById(id);
      commit('SET_CURRENT_TICKET', data);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isFetchingOne: false });
    }
  },
  async createTicket({ commit }, payload) {
    commit('SET_UI_FLAGS', { isCreating: true });
    // Clave de idempotencia por intento: evita duplicados por doble submit / reintento.
    const idempotencyKey = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    try {
      const { data } = await ticketsAPI.create(payload, idempotencyKey);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isCreating: false });
    }
  },
  async bulkAction({ commit }, { type, ids, value = null }) {
    commit('SET_UI_FLAGS', { isUpdating: true });
    try {
      const { data } = await ticketsAPI.bulkAction(type, ids, value);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isUpdating: false });
    }
  },
  async mergeTicket({ commit }, { id, targetId }) {
    const { data } = await ticketsAPI.merge(id, targetId);
    commit('SET_CURRENT_TICKET', data);
    return data;
  },
  async restoreTicket({ commit }, id) {
    const { data } = await ticketsAPI.restore(id);
    commit('SET_CURRENT_TICKET', data);
    return data;
  },
  async fetchNotificationPreferences({ commit }) {
    const { data } = await ticketsAPI.getNotificationPreferences();
    commit('SET_NOTIFICATION_PREFERENCES', data);
    return data;
  },
  async updateNotificationPreferences({ commit }, payload) {
    const { data } = await ticketsAPI.updateNotificationPreferences(payload);
    commit('SET_NOTIFICATION_PREFERENCES', data);
    return data;
  },
  async runAction({ commit }, { type, id, args = [] }) {
    commit('SET_UI_FLAGS', { isUpdating: true });
    try {
      const { data } = await ticketsAPI[type](id, ...args);
      commit('SET_CURRENT_TICKET', data);
      return data;
    } finally {
      commit('SET_UI_FLAGS', { isUpdating: false });
    }
  },
  async fetchComments({ commit }, ticketId) {
    const { data } = await ticketsAPI.getComments(ticketId);
    commit('SET_COMMENTS', data.data);
  },
  async addComment({ commit }, { ticketId, body, isPrivate, images = [] }) {
    const { data } = await ticketsAPI.addComment(
      ticketId,
      body,
      isPrivate,
      images
    );
    commit('ADD_COMMENT', data);
    return data;
  },
  async fetchCategories({ commit }) {
    const { data } = await ticketsAPI.getCategories();
    commit('SET_CATEGORIES', data.data);
  },
  async fetchMetrics({ commit }) {
    const { data } = await ticketsAPI.getMetrics();
    commit('SET_METRICS', data);
  },
  async fetchPermissions({ commit }) {
    const { data } = await ticketsAPI.getPermissions();
    commit('SET_PERMISSIONS', data);
  },
  async fetchCounts({ commit }) {
    const { data } = await ticketsAPI.getCounts();
    commit('SET_COUNTS', data);
    return data;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
