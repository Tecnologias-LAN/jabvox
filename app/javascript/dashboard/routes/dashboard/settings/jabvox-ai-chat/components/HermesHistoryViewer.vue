<script setup>
// Historial de acciones que Hermes ha ejecutado sobre la app vía su API de agente.
// Solo lectura: cada fila es un registro de JabvoxHermesActionLog escrito por el backend
// (no por Hermes). Muestra tool, estado, quién, cuándo, duración y los params saneados.
import { ref, computed, onMounted } from 'vue';
import { hermesActionLogsAPI } from 'dashboard/api/jabvox/aiChat';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SectionCard from './SectionCard.vue';

const TXT = {
  title: 'Historial de Manty',
  desc: 'Todo lo que Manty ha hecho en la app: cada acción queda auditada en el backend (nunca guarda secretos).',
  empty: 'Manty aún no ha ejecutado ninguna acción.',
  allStatuses: 'Todos los estados',
  allTools: 'Todas las herramientas',
  records: 'registro(s)',
  loadError: 'No se pudo cargar el historial.',
  colDate: 'Fecha',
  colTool: 'Herramienta',
  colStatus: 'Estado',
  colPermission: 'Permiso',
  colMs: 'ms',
  colData: 'Datos',
  prev: 'Anterior',
  next: 'Siguiente',
};

const STATUS_LABEL = {
  success: 'Éxito',
  forbidden: 'Bloqueada',
  error: 'Error',
  module_disabled: 'Módulo no activo',
};

const logs = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const loading = ref(false);
const errorMsg = ref('');
const statusFilter = ref('');
const toolFilter = ref('');

// Herramientas distintas vistas en la página actual, para el selector de filtro.
const knownTools = computed(() =>
  [...new Set(logs.value.map(l => l.tool))].sort()
);

const load = async (page = 1) => {
  loading.value = true;
  errorMsg.value = '';
  try {
    const params = { page };
    if (statusFilter.value) params.status = statusFilter.value;
    if (toolFilter.value) params.tool = toolFilter.value;
    const { data } = await hermesActionLogsAPI.getAll(params);
    logs.value = data.logs || [];
    meta.value = data.meta || meta.value;
  } catch (e) {
    errorMsg.value = e?.response?.data?.error || TXT.loadError;
  } finally {
    loading.value = false;
  }
};

const applyFilters = () => load(1);

const statusClass = status => {
  if (status === 'success') return 'bg-n-teal-3 text-n-teal-11';
  if (status === 'error') return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-amber-3 text-n-amber-11'; // forbidden / module_disabled
};

const fmtDate = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleString();
};

const fmtParams = params => {
  if (!params || !Object.keys(params).length) return '—';
  try {
    return JSON.stringify(params);
  } catch (e) {
    return '—';
  }
};

onMounted(() => load(1));
</script>

<template>
  <SectionCard :title="TXT.title" :description="TXT.desc">
    <!-- Filtros -->
    <div class="flex flex-wrap items-center gap-2 mb-3">
      <select
        v-model="statusFilter"
        class="rounded-lg border border-n-weak bg-n-alpha-2 px-2 py-1 text-sm text-n-slate-12"
        @change="applyFilters"
      >
        <option value="">{{ TXT.allStatuses }}</option>
        <option value="success">{{ STATUS_LABEL.success }}</option>
        <option value="forbidden">{{ STATUS_LABEL.forbidden }}</option>
        <option value="module_disabled">
          {{ STATUS_LABEL.module_disabled }}
        </option>
        <option value="error">{{ STATUS_LABEL.error }}</option>
      </select>

      <select
        v-model="toolFilter"
        class="rounded-lg border border-n-weak bg-n-alpha-2 px-2 py-1 text-sm text-n-slate-12"
        @change="applyFilters"
      >
        <option value="">{{ TXT.allTools }}</option>
        <option v-for="tool in knownTools" :key="tool" :value="tool">
          {{ tool }}
        </option>
      </select>

      <span class="text-xs text-n-slate-10 ml-auto">
        {{ meta.total_count }} {{ TXT.records }}
      </span>
    </div>

    <div v-if="loading" class="flex items-center justify-center py-6">
      <Spinner :size="20" />
    </div>

    <div v-else-if="errorMsg" class="text-sm text-red-500 py-2">
      {{ errorMsg }}
    </div>

    <p v-else-if="!logs.length" class="text-sm text-n-slate-10 py-2">
      {{ TXT.empty }}
    </p>

    <div v-else class="overflow-x-auto">
      <table class="w-full text-sm border-collapse">
        <thead>
          <tr class="text-left text-xs text-n-slate-10 border-b border-n-weak">
            <th class="py-2 pr-3 font-medium">{{ TXT.colDate }}</th>
            <th class="py-2 pr-3 font-medium">{{ TXT.colTool }}</th>
            <th class="py-2 pr-3 font-medium">{{ TXT.colStatus }}</th>
            <th class="py-2 pr-3 font-medium">{{ TXT.colPermission }}</th>
            <th class="py-2 pr-3 font-medium">{{ TXT.colMs }}</th>
            <th class="py-2 pr-3 font-medium">{{ TXT.colData }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="log in logs"
            :key="log.id"
            class="border-b border-n-weak/50 align-top"
          >
            <td class="py-2 pr-3 whitespace-nowrap text-n-slate-11">
              {{ fmtDate(log.created_at) }}
            </td>
            <td class="py-2 pr-3 font-mono text-n-slate-12">
              {{ log.tool }}
            </td>
            <td class="py-2 pr-3">
              <span
                class="inline-block rounded px-2 py-0.5 text-xs"
                :class="statusClass(log.status)"
              >
                {{ STATUS_LABEL[log.status] || log.status }}
              </span>
            </td>
            <td class="py-2 pr-3 text-n-slate-11">
              {{ log.permission || '—' }}
            </td>
            <td class="py-2 pr-3 text-n-slate-11">
              {{ log.duration_ms ?? '—' }}
            </td>
            <td
              class="py-2 pr-3 font-mono text-xs text-n-slate-10 max-w-md truncate"
              :title="fmtParams(log.params)"
            >
              {{ fmtParams(log.params) }}
              <span
                v-if="log.error"
                class="block text-red-400 truncate"
                :title="log.error"
              >
                {{ log.error }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Paginación -->
    <div
      v-if="meta.total_pages > 1"
      class="flex items-center justify-center gap-3 mt-3"
    >
      <Button
        size="sm"
        variant="ghost"
        label="Anterior"
        :disabled="meta.current_page <= 1 || loading"
        @click="load(meta.current_page - 1)"
      />
      <span class="text-xs text-n-slate-10">
        {{ meta.current_page }} / {{ meta.total_pages }}
      </span>
      <Button
        size="sm"
        variant="ghost"
        label="Siguiente"
        :disabled="meta.current_page >= meta.total_pages || loading"
        @click="load(meta.current_page + 1)"
      />
    </div>
  </SectionCard>
</template>
