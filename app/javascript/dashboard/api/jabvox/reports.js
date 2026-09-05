/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/reports', { accountScoped: true });

export default {
  getProducts: (params = {}) => axios.get(`${client.url}/products`, { params }),
  getAgents: (params = {}) => axios.get(`${client.url}/agents`, { params }),
  getDialer: (params = {}) => axios.get(`${client.url}/dialer`, { params }),
  getAgentStatus: () => axios.get(`${client.url}/agent_status`),
  // Actividad de Hermes (bot IA): totales, por herramienta, por día, recientes.
  getHermesActivity: (params = {}) =>
    axios.get(`${client.url}/hermes_activity`, { params }),
  setDialerState: state =>
    axios.patch(`${client.url}/set_dialer_state`, { state }),

  // Drill-down records for a single metric, filtered by agent + date range.
  // `config` accepts an AbortController signal so the store can cancel stale
  // requests when the user changes filters quickly.
  getAnalyticsRecords: (metricKey, params = {}, config = {}) =>
    axios.get(`${client.url}/analytics/${metricKey}/records`, {
      params,
      ...config,
    }),
  // Totals breakdown + filter config/options for a metric's drill-down.
  getAnalyticsBreakdown: (metricKey, params = {}, config = {}) =>
    axios.get(`${client.url}/analytics/${metricKey}/breakdown`, {
      params,
      ...config,
    }),
};
