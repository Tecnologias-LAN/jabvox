import {
  productsAPI,
  discountsAPI,
  orderStatusConfigsAPI,
  currenciesAPI,
  itemTypesAPI,
  unitsOfMeasureAPI,
  taxRatesAPI,
  integrationConfigAPI,
} from '../../../api/jabvox/products';

const state = {
  products: [],
  discounts: [],
  orderStatusConfigs: [],
  currencies: [],
  itemTypes: [],
  unitsOfMeasure: [],
  taxRates: [],
  integrationConfig: null,
  uiFlags: {
    isFetchingProducts: false,
    isSavingProduct: false,
    isFetchingDiscounts: false,
    isSavingDiscount: false,
    isFetchingStatuses: false,
    isSavingStatus: false,
    isFetchingCurrencies: false,
    isSavingCurrency: false,
    isFetchingItemTypes: false,
    isSavingItemType: false,
    isFetchingUnits: false,
    isSavingUnit: false,
    isFetchingTaxRates: false,
    isSavingTaxRate: false,
    isFetchingConfig: false,
    isSavingConfig: false,
    isImportingProducts: false,
  },
};

const buildCRUD = (apiClient, listKey, flagFetch, flagSave, recordKey) => ({
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { [flagFetch]: true });
    try {
      const { data } = await apiClient.getAll();
      commit('SET_LIST', {
        key: listKey,
        items: Array.isArray(data) ? data : [],
      });
    } catch {
      // ignore
    } finally {
      commit('SET_UI_FLAG', { [flagFetch]: false });
    }
  },
  create: async ({ commit }, payload) => {
    commit('SET_UI_FLAG', { [flagSave]: true });
    try {
      const { data } = await apiClient.create({ [recordKey]: payload });
      commit('ADD_ITEM', { key: listKey, item: data });
      return data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { [flagSave]: false });
    }
  },
  update: async ({ commit }, { id, ...payload }) => {
    commit('SET_UI_FLAG', { [flagSave]: true });
    try {
      const { data } = await apiClient.update(id, { [recordKey]: payload });
      commit('UPDATE_ITEM', { key: listKey, item: data });
      return data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { [flagSave]: false });
    }
  },
  destroy: async ({ commit }, id) => {
    commit('SET_UI_FLAG', { [flagSave]: true });
    try {
      await apiClient.destroy(id);
      commit('REMOVE_ITEM', { key: listKey, id });
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { [flagSave]: false });
    }
  },
});

export const actions = {
  ...Object.fromEntries(
    Object.entries(
      buildCRUD(
        productsAPI,
        'products',
        'isFetchingProducts',
        'isSavingProduct',
        'product'
      )
    ).map(([k, v]) => [`${k}Product`, v])
  ),
  ...Object.fromEntries(
    Object.entries(
      buildCRUD(
        discountsAPI,
        'discounts',
        'isFetchingDiscounts',
        'isSavingDiscount',
        'discount'
      )
    ).map(([k, v]) => [`${k}Discount`, v])
  ),
  ...Object.fromEntries(
    Object.entries(
      buildCRUD(
        orderStatusConfigsAPI,
        'orderStatusConfigs',
        'isFetchingStatuses',
        'isSavingStatus',
        'status_config'
      )
    ).map(([k, v]) => [`${k}Status`, v])
  ),
  ...Object.fromEntries(
    Object.entries(
      buildCRUD(
        currenciesAPI,
        'currencies',
        'isFetchingCurrencies',
        'isSavingCurrency',
        'currency'
      )
    ).map(([k, v]) => [`${k}Currency`, v])
  ),
  ...Object.fromEntries(
    Object.entries(
      buildCRUD(
        itemTypesAPI,
        'itemTypes',
        'isFetchingItemTypes',
        'isSavingItemType',
        'item_type'
      )
    ).map(([k, v]) => [`${k}ItemType`, v])
  ),
  ...Object.fromEntries(
    Object.entries(
      buildCRUD(
        unitsOfMeasureAPI,
        'unitsOfMeasure',
        'isFetchingUnits',
        'isSavingUnit',
        'unit'
      )
    ).map(([k, v]) => [`${k}Unit`, v])
  ),
  ...Object.fromEntries(
    Object.entries(
      buildCRUD(
        taxRatesAPI,
        'taxRates',
        'isFetchingTaxRates',
        'isSavingTaxRate',
        'tax_rate'
      )
    ).map(([k, v]) => [`${k}TaxRate`, v])
  ),

  fetchIntegrationConfig: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetchingConfig: true });
    try {
      const { data } = await integrationConfigAPI.get();
      commit('SET_INTEGRATION_CONFIG', data);
    } catch {
      // ignore
    } finally {
      commit('SET_UI_FLAG', { isFetchingConfig: false });
    }
  },

  saveIntegrationConfig: async ({ commit }, payload) => {
    commit('SET_UI_FLAG', { isSavingConfig: true });
    try {
      const { data } = await integrationConfigAPI.update({ config: payload });
      commit('SET_INTEGRATION_CONFIG', data);
      return data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isSavingConfig: false });
    }
  },

  disconnectIntegration: async ({ commit }) => {
    commit('SET_UI_FLAG', { isSavingConfig: true });
    try {
      await integrationConfigAPI.destroy();
      commit('SET_INTEGRATION_CONFIG', null);
    } catch (error) {
      throw new Error(error?.response?.data?.message || error.message);
    } finally {
      commit('SET_UI_FLAG', { isSavingConfig: false });
    }
  },

  importProducts: async ({ commit, dispatch }) => {
    commit('SET_UI_FLAG', { isImportingProducts: true });
    try {
      const { data } = await productsAPI.import();
      await Promise.allSettled([
        dispatch('fetchProduct'),
        dispatch('fetchCurrency'),
        dispatch('fetchItemType'),
        dispatch('fetchUnit'),
      ]);
      return data;
    } catch (error) {
      throw new Error(
        error?.response?.data?.error ||
          error?.response?.data?.message ||
          error.message
      );
    } finally {
      commit('SET_UI_FLAG', { isImportingProducts: false });
    }
  },
};

export const mutations = {
  SET_UI_FLAG(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  SET_LIST(_state, { key, items }) {
    _state[key] = items;
  },
  ADD_ITEM(_state, { key, item }) {
    _state[key] = [..._state[key], item];
  },
  UPDATE_ITEM(_state, { key, item }) {
    const idx = _state[key].findIndex(i => i.id === item.id);
    if (idx !== -1) _state[key].splice(idx, 1, item);
  },
  REMOVE_ITEM(_state, { key, id }) {
    _state[key] = _state[key].filter(i => i.id !== id);
  },
  SET_INTEGRATION_CONFIG(_state, config) {
    _state.integrationConfig = config;
  },
};

export const getters = {
  getProducts: s => s.products,
  getDiscounts: s => s.discounts,
  getOrderStatusConfigs: s => s.orderStatusConfigs,
  getCurrencies: s => s.currencies,
  getItemTypes: s => s.itemTypes,
  getUnitsOfMeasure: s => s.unitsOfMeasure,
  getTaxRates: s => s.taxRates,
  getIntegrationConfig: s => s.integrationConfig,
  getUIFlags: s => s.uiFlags,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
