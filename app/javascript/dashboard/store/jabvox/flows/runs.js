import { defineStore } from 'pinia';
import { ref } from 'vue';
import { runsAPI } from 'dashboard/api/jabvox/flows';
import { apiError } from './flows';

export const useRunsStore = defineStore('jabvoxFlowRuns', () => {
  const items = ref([]);
  const total = ref(0);
  const stats = ref(null);
  const detail = ref(null);
  const loading = ref(false);
  const error = ref(null);

  async function fetchPage(params = {}) {
    loading.value = true;
    error.value = null;
    try {
      const { data } = await runsAPI.list(params);
      items.value = data.items;
      total.value = data.total;
      return data;
    } catch (e) {
      error.value = apiError(e);
      return null;
    } finally {
      loading.value = false;
    }
  }

  async function fetchStats(days) {
    try {
      const { data } = await runsAPI.stats(days);
      stats.value = data;
    } catch {
      stats.value = null;
    }
  }

  async function fetchDetail(runId) {
    loading.value = true;
    error.value = null;
    try {
      const { data } = await runsAPI.get(runId);
      detail.value = data;
      return data;
    } catch (e) {
      error.value = apiError(e);
      return null;
    } finally {
      loading.value = false;
    }
  }

  async function resume(runId, payload = {}) {
    const { data } = await runsAPI.resume(runId, payload);
    return data;
  }

  return {
    items,
    total,
    stats,
    detail,
    loading,
    error,
    fetchPage,
    fetchStats,
    fetchDetail,
    resume,
  };
});
