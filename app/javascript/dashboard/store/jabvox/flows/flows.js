import { defineStore } from 'pinia';
import { ref } from 'vue';
import { flowsAPI } from 'dashboard/api/jabvox/flows';

// Mensaje legible del error de la API, con el detalle del backend si lo trae.
export function apiError(e) {
  return e?.response?.data?.error || e?.message || 'Error desconocido';
}

// Problemas de validación que acompañan a un rechazo al guardar o al activar.
export function graphIssues(e) {
  const issues = e?.response?.data?.validation?.issues;
  return Array.isArray(issues) ? issues : null;
}

export const useFlowsStore = defineStore('jabvoxFlows', () => {
  const flows = ref([]);
  const current = ref(null);
  const runs = ref([]);
  const loading = ref(false);
  const saving = ref(false);
  const error = ref(null);

  async function fetchAll(params = {}) {
    loading.value = true;
    error.value = null;
    try {
      const { data } = await flowsAPI.list(params);
      flows.value = data;
    } catch (e) {
      error.value = apiError(e);
    } finally {
      loading.value = false;
    }
  }

  async function fetchOne(id) {
    loading.value = true;
    error.value = null;
    try {
      const { data } = await flowsAPI.get(id);
      current.value = data;
      return data;
    } catch (e) {
      error.value = apiError(e);
      return null;
    } finally {
      loading.value = false;
    }
  }

  async function create(payload) {
    const { data } = await flowsAPI.create(payload);
    flows.value = [data, ...flows.value];
    return data;
  }

  async function update(id, payload) {
    const { data } = await flowsAPI.update(id, payload);
    flows.value = flows.value.map(f => (f.id === id ? data : f));
    if (current.value?.id === id) current.value = data;
    return data;
  }

  async function remove(id) {
    await flowsAPI.delete(id);
    flows.value = flows.value.filter(f => f.id !== id);
  }

  async function duplicate(id) {
    const { data } = await flowsAPI.duplicate(id);
    flows.value = [data, ...flows.value];
    return data;
  }

  // Guarda el grafo como versión nueva. Sin `strict` el backend valida en modo
  // permisivo, que es lo que necesita el autoguardado del editor.
  async function saveVersion(id, graph, strict = false) {
    saving.value = true;
    try {
      const { data } = await flowsAPI.saveVersion(id, graph, strict);
      current.value = data;
      return data;
    } finally {
      saving.value = false;
    }
  }

  async function validate(id, graph) {
    const { data } = await flowsAPI.validate(id, graph);
    return data;
  }

  async function setStatus(id, status) {
    return update(id, { status });
  }

  async function fetchRuns(id, limit = 10) {
    const { data } = await flowsAPI.listRuns(id, limit);
    runs.value = data;
    return data;
  }

  async function run(id, payload = {}) {
    const { data } = await flowsAPI.run(id, payload);
    return data;
  }

  async function runNode(id, nodeId, payload = {}, options = {}) {
    const { data } = await flowsAPI.runNode(id, nodeId, payload, options);
    return data;
  }

  async function runFrom(id, nodeId, payload = {}) {
    const { data } = await flowsAPI.runFrom(id, nodeId, payload);
    return data;
  }

  return {
    flows,
    current,
    runs,
    loading,
    saving,
    error,
    fetchAll,
    fetchOne,
    create,
    update,
    remove,
    duplicate,
    saveVersion,
    validate,
    setStatus,
    fetchRuns,
    run,
    runNode,
    runFrom,
  };
});
