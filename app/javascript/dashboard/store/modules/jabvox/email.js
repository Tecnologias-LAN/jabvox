import {
  smtpConfigAPI,
  emailTemplatesAPI,
  stageAutomationsAPI,
  calendarSettingAPI,
} from 'dashboard/api/jabvox/email';

const state = {
  smtpConfig: null,
  calendarSetting: null,
  templates: [],
  templatesMeta: { count: 0, limit: 20 },
  automations: [],
  uiFlags: {
    isFetchingSmtp: false,
    isFetchingTemplates: false,
    isFetchingAutomations: false,
    isSaving: false,
    isSavingCalendar: false,
    isTesting: false,
    isSendingTest: false,
  },
};

const getters = {
  getSmtpConfig: s => s.smtpConfig,
  getCalendarSetting: s => s.calendarSetting,
  getTemplates: s => s.templates,
  getTemplatesMeta: s => s.templatesMeta,
  getAutomations: s => s.automations,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_SMTP_CONFIG(s, v) {
    s.smtpConfig = v;
  },
  SET_CALENDAR_SETTING(s, v) {
    s.calendarSetting = v;
  },
  SET_TEMPLATES(s, v) {
    s.templates = v;
  },
  SET_TEMPLATES_META(s, v) {
    s.templatesMeta = v;
  },
  SET_AUTOMATIONS(s, v) {
    s.automations = v;
  },
  SET_UI_FLAG(s, f) {
    s.uiFlags = { ...s.uiFlags, ...f };
  },
  ADD_TEMPLATE(s, v) {
    s.templates = [v, ...s.templates];
  },
  UPDATE_TEMPLATE(s, v) {
    s.templates = s.templates.map(t => (t.id === v.id ? v : t));
  },
  REMOVE_TEMPLATE(s, id) {
    s.templates = s.templates.filter(t => t.id !== id);
  },
  ADD_AUTOMATION(s, v) {
    s.automations = [...s.automations, v];
  },
  UPDATE_AUTOMATION(s, v) {
    s.automations = s.automations.map(a => (a.id === v.id ? v : a));
  },
  REMOVE_AUTOMATION(s, id) {
    s.automations = s.automations.filter(a => a.id !== id);
  },
};

const actions = {
  async fetchSmtpConfig({ commit }) {
    commit('SET_UI_FLAG', { isFetchingSmtp: true });
    try {
      const { data } = await smtpConfigAPI.get();
      commit('SET_SMTP_CONFIG', data);
    } catch {
      commit('SET_SMTP_CONFIG', null);
    } finally {
      commit('SET_UI_FLAG', { isFetchingSmtp: false });
    }
  },

  async saveSmtpConfig({ commit, state: s }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const fn = s.smtpConfig?.id ? smtpConfigAPI.update : smtpConfigAPI.save;
      const { data } = await fn(payload);
      commit('SET_SMTP_CONFIG', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async fetchCalendarSetting({ commit }) {
    try {
      const { data } = await calendarSettingAPI.get();
      commit('SET_CALENDAR_SETTING', data);
    } catch {
      commit('SET_CALENDAR_SETTING', {
        reminders_enabled: false,
        reminder_minutes: [],
      });
    }
  },

  async saveCalendarSetting({ commit }, payload) {
    commit('SET_UI_FLAG', { isSavingCalendar: true });
    try {
      const { data } = await calendarSettingAPI.update(payload);
      commit('SET_CALENDAR_SETTING', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSavingCalendar: false });
    }
  },

  async testSmtpConfig({ commit }) {
    commit('SET_UI_FLAG', { isTesting: true });
    try {
      await smtpConfigAPI.test();
      return true;
    } finally {
      commit('SET_UI_FLAG', { isTesting: false });
    }
  },

  async fetchTemplates({ commit }) {
    commit('SET_UI_FLAG', { isFetchingTemplates: true });
    try {
      const { data } = await emailTemplatesAPI.getAll();
      commit('SET_TEMPLATES', data.templates);
      commit('SET_TEMPLATES_META', data.meta);
    } finally {
      commit('SET_UI_FLAG', { isFetchingTemplates: false });
    }
  },

  async createTemplate({ commit }, payload) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await emailTemplatesAPI.create(payload);
      commit('ADD_TEMPLATE', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async updateTemplate({ commit }, { id, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await emailTemplatesAPI.update(id, payload);
      commit('UPDATE_TEMPLATE', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async deleteTemplate({ commit }, id) {
    await emailTemplatesAPI.destroy(id);
    commit('REMOVE_TEMPLATE', id);
  },

  async sendTestTemplate({ commit }, { id, to }) {
    commit('SET_UI_FLAG', { isSendingTest: true });
    try {
      await emailTemplatesAPI.sendTest(id, { to });
      return true;
    } finally {
      commit('SET_UI_FLAG', { isSendingTest: false });
    }
  },

  async fetchAutomations({ commit }, { funnelId, stageId }) {
    commit('SET_UI_FLAG', { isFetchingAutomations: true });
    try {
      const { data } = await stageAutomationsAPI.getAll(funnelId, stageId);
      commit('SET_AUTOMATIONS', data.automations);
    } finally {
      commit('SET_UI_FLAG', { isFetchingAutomations: false });
    }
  },

  async createAutomation({ commit }, { funnelId, stageId, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await stageAutomationsAPI.create(
        funnelId,
        stageId,
        payload
      );
      commit('ADD_AUTOMATION', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async updateAutomation({ commit }, { funnelId, stageId, id, ...payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await stageAutomationsAPI.update(
        funnelId,
        stageId,
        id,
        payload
      );
      commit('UPDATE_AUTOMATION', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async deleteAutomation({ commit }, { funnelId, stageId, id }) {
    await stageAutomationsAPI.destroy(funnelId, stageId, id);
    commit('REMOVE_AUTOMATION', id);
  },
};

export default { namespaced: true, state, getters, mutations, actions };
