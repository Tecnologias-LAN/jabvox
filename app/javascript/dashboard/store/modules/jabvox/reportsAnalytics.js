import reportsAPI from 'dashboard/api/jabvox/reports';

// Store for the agent-report drill-down (records for one metric filtered by
// agent + date range). Stale-request cancellation: each fetch aborts the
// previous in-flight one, so rapid filter changes never render an outdated
// response.

const state = {
  records: [],
  recordsMeta: null,
  breakdown: null, // { total, rows, breakdown_label, filters_config, filter_options }
  uiFlags: {
    isFetchingRecords: false,
    recordsError: false,
    isFetchingBreakdown: false,
  },
};

let recordsController = null;
let breakdownController = null;

const getters = {
  getRecords: s => s.records,
  getRecordsMeta: s => s.recordsMeta,
  getBreakdown: s => s.breakdown,
  getAnalyticsUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_RECORDS(s, { data, meta, append }) {
    s.records = append ? [...s.records, ...(data || [])] : data || [];
    s.recordsMeta = meta || null;
  },
  SET_BREAKDOWN(s, breakdown) {
    s.breakdown = breakdown;
  },
  SET_UI_FLAG(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
};

const actions = {
  async fetchRecords({ commit }, { metricKey, params = {}, append = false }) {
    if (recordsController) recordsController.abort();
    recordsController = new AbortController();
    commit('SET_UI_FLAG', { isFetchingRecords: true, recordsError: false });
    try {
      const { data } = await reportsAPI.getAnalyticsRecords(metricKey, params, {
        signal: recordsController.signal,
      });
      commit('SET_RECORDS', { data: data.data, meta: data.meta, append });
      return data;
    } catch (e) {
      if (e.name === 'CanceledError' || e.code === 'ERR_CANCELED') return null;
      commit('SET_UI_FLAG', { recordsError: true });
      throw e;
    } finally {
      commit('SET_UI_FLAG', { isFetchingRecords: false });
    }
  },

  async fetchBreakdown({ commit }, { metricKey, params = {} }) {
    if (breakdownController) breakdownController.abort();
    breakdownController = new AbortController();
    commit('SET_UI_FLAG', { isFetchingBreakdown: true });
    try {
      const { data } = await reportsAPI.getAnalyticsBreakdown(
        metricKey,
        params,
        {
          signal: breakdownController.signal,
        }
      );
      commit('SET_BREAKDOWN', data);
      return data;
    } catch (e) {
      if (e.name === 'CanceledError' || e.code === 'ERR_CANCELED') return null;
      throw e;
    } finally {
      commit('SET_UI_FLAG', { isFetchingBreakdown: false });
    }
  },

  resetRecords({ commit }) {
    commit('SET_RECORDS', { data: [], meta: null, append: false });
    commit('SET_BREAKDOWN', null);
  },
};

export default { namespaced: true, state, getters, mutations, actions };
