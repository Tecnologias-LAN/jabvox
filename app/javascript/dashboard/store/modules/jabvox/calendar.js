import calendarAPI from 'dashboard/api/jabvox/calendar';

const state = {
  events: [],
  externalPeople: [],
  uiFlags: {
    isFetching: false,
    isSaving: false,
    isFetchingPeople: false,
  },
};

const getters = {
  getEvents: s => s.events,
  getExternalPeople: s => s.externalPeople,
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
      // create returns an array (one entry per slot)
      const created = Array.isArray(data) ? data : [data];
      created.forEach(event => commit('ADD_EVENT', event));
      return created;
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
  deleteEvent: async ({ commit }, { id, scope } = {}) => {
    await calendarAPI.destroy(id, scope ? { scope } : {});
    commit('REMOVE_EVENT', id);
  },

  // External people
  fetchExternalPeople: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetchingPeople: true });
    try {
      const { data } = await calendarAPI.getExternalPeople();
      commit('SET_EXTERNAL_PEOPLE', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingPeople: false });
    }
  },
  createExternalPerson: async ({ commit }, payload) => {
    const { data } = await calendarAPI.createExternalPerson(payload);
    commit('ADD_EXTERNAL_PERSON', data);
    return data;
  },
  updateExternalPerson: async ({ commit }, { id, ...payload }) => {
    const { data } = await calendarAPI.updateExternalPerson(id, payload);
    commit('UPDATE_EXTERNAL_PERSON', data);
    return data;
  },
  deleteExternalPerson: async ({ commit }, id) => {
    await calendarAPI.destroyExternalPerson(id);
    commit('REMOVE_EXTERNAL_PERSON', id);
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
  SET_EXTERNAL_PEOPLE: (s, people) => {
    s.externalPeople = people;
  },
  ADD_EXTERNAL_PERSON: (s, person) => {
    s.externalPeople = [...s.externalPeople, person];
  },
  UPDATE_EXTERNAL_PERSON: (s, person) => {
    s.externalPeople = s.externalPeople.map(p =>
      p.id === person.id ? person : p
    );
  },
  REMOVE_EXTERNAL_PERSON: (s, id) => {
    s.externalPeople = s.externalPeople.filter(p => p.id !== id);
  },
  SET_UI_FLAG: (s, flags) => {
    Object.assign(s.uiFlags, flags);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
