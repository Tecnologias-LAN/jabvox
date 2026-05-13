import { formsAPI, formConfigAPI } from 'dashboard/api/jabvox/forms';

const state = {
  forms: [],
  formConfig: null,
  uiFlags: {
    isFetching: false,
    isSaving: false,
    isDeleting: false,
    isFetchingConfig: false,
    isSavingConfig: false,
  },
};

const getters = {
  getForms: s => s.forms,
  getFormConfig: s => s.formConfig,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_FORMS(s, v) {
    s.forms = v;
  },
  ADD_FORM(s, v) {
    s.forms = [v, ...s.forms];
  },
  UPDATE_FORM(s, v) {
    s.forms = s.forms.map(f => (f.id === v.id ? v : f));
  },
  REMOVE_FORM(s, id) {
    s.forms = s.forms.filter(f => f.id !== id);
  },
  SET_FORM_CONFIG(s, v) {
    s.formConfig = v;
  },
  SET_UI_FLAG(s, { flag, value }) {
    s.uiFlags[flag] = value;
  },
};

const actions = {
  async fetchForms({ commit }) {
    commit('SET_UI_FLAG', { flag: 'isFetching', value: true });
    try {
      const { data } = await formsAPI.getAll();
      commit('SET_FORMS', data);
    } finally {
      commit('SET_UI_FLAG', { flag: 'isFetching', value: false });
    }
  },

  async createForm({ commit }, payload) {
    commit('SET_UI_FLAG', { flag: 'isSaving', value: true });
    try {
      const { data } = await formsAPI.create(payload);
      commit('ADD_FORM', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSaving', value: false });
    }
  },

  async updateForm({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { flag: 'isSaving', value: true });
    try {
      const { data } = await formsAPI.update(id, payload);
      commit('UPDATE_FORM', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSaving', value: false });
    }
  },

  async deleteForm({ commit }, id) {
    commit('SET_UI_FLAG', { flag: 'isDeleting', value: true });
    try {
      await formsAPI.destroy(id);
      commit('REMOVE_FORM', id);
    } finally {
      commit('SET_UI_FLAG', { flag: 'isDeleting', value: false });
    }
  },

  async fetchFormConfig({ commit }) {
    commit('SET_UI_FLAG', { flag: 'isFetchingConfig', value: true });
    try {
      const { data } = await formConfigAPI.get();
      commit('SET_FORM_CONFIG', data);
    } finally {
      commit('SET_UI_FLAG', { flag: 'isFetchingConfig', value: false });
    }
  },

  async updateFormConfig({ commit }, payload) {
    commit('SET_UI_FLAG', { flag: 'isSavingConfig', value: true });
    try {
      const { data } = await formConfigAPI.update(payload);
      commit('SET_FORM_CONFIG', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { flag: 'isSavingConfig', value: false });
    }
  },
};

export default { namespaced: true, state, getters, mutations, actions };
