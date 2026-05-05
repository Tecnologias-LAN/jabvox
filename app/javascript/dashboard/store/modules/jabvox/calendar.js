import calendarAPI from 'dashboard/api/jabvox/calendar';

const state = {
  events: [],
  uiFlags: {
    isFetching: false,
    isSaving: false,
  },
};

const getters = {
  getEvents: s => s.events,
  getUIFlags: s => s.uiFlags,
};

const actions = {
  fetchEvents: async ({ commit }, params = {}) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await calendarAPI.getEvents(params);
      commit('SET_EVENTS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  createEvent: async ({ commit }, payload) => {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await calendarAPI.create(payload);
      commit('ADD_EVENT', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },
  updateEvent: async ({ commit }, { id, ...payload }) => {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await calendarAPI.update(id, payload);
      commit('UPDATE_EVENT', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },
  deleteEvent: async ({ commit }, id) => {
    await calendarAPI.destroy(id);
    commit('REMOVE_EVENT', id);
  },
};

const mutations = {
  SET_EVENTS: (s, events) => {
    s.events = events;
  },
  ADD_EVENT: (s, event) => {
    s.events = [...s.events, event];
  },
  UPDATE_EVENT: (s, event) => {
    s.events = s.events.map(e => (e.id === event.id ? event : e));
  },
  REMOVE_EVENT: (s, id) => {
    s.events = s.events.filter(e => e.id !== id);
  },
  SET_UI_FLAG: (s, flags) => {
    Object.assign(s.uiFlags, flags);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
