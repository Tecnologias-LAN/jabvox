<script setup>
// Modal reutilizable para guardar una consulta (visual o SQL) como widget en un dashboard.
// Emite 'save' con { title, dashboardId, widgetType }. El padre arma el payload (query_spec
// o custom_sql) porque solo él sabe qué está guardando.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';

defineProps({
  open: { type: Boolean, default: false },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'save']);

const { t } = useI18n();
const dashboardsStore = useAnalyticsDashboardsStore();

const title = ref('');
const dashboardId = ref(null);
const widgetType = ref('table');

const dashboards = computed(() => dashboardsStore.list);
const WIDGET_TYPES = [
  { value: 'number', label: 'Número' },
  { value: 'table', label: 'Tabla' },
  { value: 'bar', label: 'Barras' },
  { value: 'line', label: 'Líneas' },
  { value: 'pie', label: 'Pastel' },
  { value: 'donut', label: 'Dona' },
];

const canSave = computed(() => title.value.trim() && dashboardId.value);

onMounted(() => {
  dashboardsStore.fetchDashboards().then(() => {
    if (dashboards.value.length) dashboardId.value = dashboards.value[0].id;
  });
});

const submit = () => {
  if (!canSave.value) return;
  emit('save', {
    title: title.value.trim(),
    dashboardId: dashboardId.value,
    widgetType: widgetType.value,
  });
};

const controlClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-16"
  >
    <div
      class="w-full max-w-lg rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
    >
      <div class="mb-4 flex items-center justify-between">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.SQL.SAVE_TO_DASHBOARD') }}
        </h3>
        <button
          type="button"
          class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <div class="flex flex-col gap-3">
        <div>
          <label class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.SQL.WIDGET_TITLE') }}
          </label>
          <input
            v-model="title"
            type="text"
            :class="controlClass"
            :placeholder="t('JABVOX_ANALYTICS.SQL.WIDGET_TITLE')"
          />
        </div>
        <div>
          <label class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.SQL.TARGET_DASHBOARD') }}
          </label>
          <select v-model="dashboardId" :class="controlClass">
            <option :value="null" disabled>—</option>
            <option v-for="d in dashboards" :key="d.id" :value="d.id">
              {{ d.nameJabvox }}
            </option>
          </select>
        </div>
        <div>
          <label class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.SQL.WIDGET_TYPE') }}
          </label>
          <select v-model="widgetType" :class="controlClass">
            <option v-for="w in WIDGET_TYPES" :key="w.value" :value="w.value">
              {{ w.label }}
            </option>
          </select>
        </div>
      </div>

      <div class="mt-6 flex items-center justify-end gap-3">
        <button
          type="button"
          class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
          @click="emit('close')"
        >
          {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="saving || !canSave"
          @click="submit"
        >
          <span
            v-if="saving"
            class="i-lucide-loader-circle size-4 animate-spin"
          />
          {{ t('JABVOX_ANALYTICS.COMMON.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>
