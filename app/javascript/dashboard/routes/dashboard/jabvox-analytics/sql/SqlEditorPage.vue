<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsQueryStore } from 'dashboard/stores/jabvox/analytics/query';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';
import { useAnalyticsWidgetsStore } from 'dashboard/stores/jabvox/analytics/widgets';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsEmptyState from '../components/AnalyticsEmptyState.vue';
import AnalyticsDataTable from '../data-sources/AnalyticsDataTable.vue';
import SqlValidationFeedback from './SqlValidationFeedback.vue';

const { t } = useI18n();
const route = useRoute();
const dsStore = useAnalyticsDataSourcesStore();
const queryStore = useAnalyticsQueryStore();
const dashboardsStore = useAnalyticsDashboardsStore();
const widgetsStore = useAnalyticsWidgetsStore();
const capabilities = useAnalyticsCapabilitiesStore();
const { showError } = useAnalyticsError();

const selectedDsId = ref(null);

const canUseSql = computed(() => capabilities.canUseCustomSql);
const dataSources = computed(() => dsStore.list);

const sql = computed({
  get: () => queryStore.sql,
  set: value => {
    queryStore.sql = value;
  },
});

// ─── Guardar la query como widget en un dashboard ───
const showSaveModal = ref(false);
const saving = ref(false);
const saveForm = ref({ title: '', dashboardId: null, widgetType: 'number' });
const dashboards = computed(() => dashboardsStore.list);
// Tipos de visualización más comunes para una query (el número grande = "number").
const WIDGET_TYPES = [
  { value: 'number', label: 'Número' },
  { value: 'table', label: 'Tabla' },
  { value: 'bar', label: 'Barras' },
  { value: 'line', label: 'Líneas' },
  { value: 'pie', label: 'Pastel' },
];

const openSaveModal = () => {
  saveForm.value = {
    title: '',
    dashboardId: dashboards.value[0]?.id || null,
    widgetType: 'number',
  };
  dashboardsStore.fetchDashboards().catch(() => {});
  showSaveModal.value = true;
};

const saveAsWidget = async () => {
  if (!saveForm.value.title.trim() || !saveForm.value.dashboardId) return;
  saving.value = true;
  try {
    await widgetsStore.addWidget(saveForm.value.dashboardId, {
      widget_type_jabvox: saveForm.value.widgetType,
      title_jabvox: saveForm.value.title.trim(),
      data_source_id: selectedDsId.value,
      custom_sql_jabvox: sql.value,
      query_spec_jabvox: {},
      config_jabvox: {},
    });
    useAlert(t('JABVOX_ANALYTICS.SQL.SAVED_WIDGET'));
    showSaveModal.value = false;
  } catch (error) {
    showError(error);
  } finally {
    saving.value = false;
  }
};

const validation = computed(() => queryStore.validation);
const rows = computed(() => queryStore.result.rows);
const resultColumns = computed(() => queryStore.result.columns);
const validating = computed(() => queryStore.uiFlags.validating);
const running = computed(() => queryStore.uiFlags.running);

const canExecute = computed(() =>
  Boolean(selectedDsId.value && sql.value.trim())
);

// Motivo por el que no se puede ejecutar, para decirlo en vez de dejar el botón gris.
const blockedReason = computed(() => {
  if (!dataSources.value.length)
    return t('JABVOX_ANALYTICS.SQL.NO_DATA_SOURCES');
  if (!selectedDsId.value) return t('JABVOX_ANALYTICS.SQL.PICK_DATA_SOURCE');
  if (!sql.value.trim()) return t('JABVOX_ANALYTICS.SQL.WRITE_QUERY');
  return '';
});

const dataSourcesRoute = computed(() => ({
  name: 'jabvox_analytics_data_sources',
  params: { accountId: route.params.accountId },
}));

const validate = async () => {
  if (!canExecute.value) return;
  try {
    await queryStore.validateSql(selectedDsId.value);
  } catch (error) {
    showError(error);
  }
};

const run = async () => {
  if (!canExecute.value) return;
  try {
    await queryStore.runSql(selectedDsId.value);
  } catch (error) {
    showError(error);
  }
};

const hasResult = computed(() => resultColumns.value.length > 0);

onMounted(() => {
  if (canUseSql.value) dsStore.fetch().catch(error => showError(error));
});

const controlClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div>
    <AnalyticsPageHeader :title="t('JABVOX_ANALYTICS.SQL.TITLE')" />

    <AnalyticsEmptyState
      v-if="!canUseSql"
      icon="i-lucide-lock"
      :title="t('JABVOX_ANALYTICS.SQL.NO_PERMISSION')"
    />

    <template v-else>
      <!-- Sin fuentes configuradas los botones quedaban grises SIN explicación y parecía
           que la pantalla estaba rota. Se avisa y se enlaza a donde se crean. -->
      <div
        v-if="!dataSources.length"
        class="mb-4 flex flex-wrap items-center gap-2 rounded-lg border border-n-amber-6 bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
      >
        <span class="i-lucide-triangle-alert size-4 shrink-0" />
        <span>{{ t('JABVOX_ANALYTICS.SQL.NO_DATA_SOURCES') }}</span>
        <router-link
          :to="dataSourcesRoute"
          class="font-medium underline underline-offset-2"
        >
          {{ t('JABVOX_ANALYTICS.SQL.NO_DATA_SOURCES_CTA') }}
        </router-link>
      </div>

      <div class="mb-4 max-w-sm">
        <label class="mb-1 block text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.DATA_SOURCE') }}
        </label>
        <select
          :value="selectedDsId"
          :class="controlClass"
          @change="selectedDsId = Number($event.target.value) || null"
        >
          <option :value="null">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
          <option v-for="ds in dataSources" :key="ds.id" :value="ds.id">
            {{ ds.nameJabvox }}
          </option>
        </select>
      </div>

      <div
        class="mb-3 flex items-center gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-11"
      >
        <span class="i-lucide-info size-4 shrink-0" />
        {{ t('JABVOX_ANALYTICS.SQL.READ_ONLY_NOTICE') }}
      </div>

      <textarea
        v-model="sql"
        rows="8"
        spellcheck="false"
        class="block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 font-mono text-sm text-n-slate-12 outline-none focus:border-n-strong focus:ring-1 focus:ring-n-brand"
        placeholder="SELECT * FROM ..."
      />

      <div class="mt-3 flex flex-wrap items-center gap-3">
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="!canExecute || validating"
          @click="validate"
        >
          <span
            v-if="validating"
            class="i-lucide-loader-circle size-4 animate-spin"
          />
          {{ t('JABVOX_ANALYTICS.SQL.VALIDATE') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="!canExecute || running"
          @click="run"
        >
          <span
            v-if="running"
            class="i-lucide-loader-circle size-4 animate-spin"
          />
          <span v-else class="i-lucide-play size-4" />
          {{ t('JABVOX_ANALYTICS.SQL.RUN') }}
        </button>
        <button
          v-if="hasResult"
          type="button"
          class="inline-flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1"
          @click="openSaveModal"
        >
          <span class="i-lucide-layout-dashboard size-4" />
          {{ t('JABVOX_ANALYTICS.SQL.SAVE_TO_DASHBOARD') }}
        </button>

        <!-- Por qué no se puede ejecutar, en vez de dejar el botón gris sin explicación -->
        <span
          v-if="blockedReason"
          class="inline-flex items-center gap-1.5 text-xs text-n-slate-10"
        >
          <span class="i-lucide-info size-3.5 shrink-0" />
          {{ blockedReason }}
        </span>
      </div>

      <div v-if="validation" class="mt-3">
        <SqlValidationFeedback :validation="validation" />
      </div>

      <div class="mt-4">
        <AnalyticsDataTable
          :rows="rows"
          :columns="resultColumns"
          :loading="running"
        />
      </div>
    </template>

    <!-- Modal: guardar la query como widget en un dashboard -->
    <div
      v-if="showSaveModal"
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
            @click="showSaveModal = false"
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
              v-model="saveForm.title"
              type="text"
              :class="controlClass"
              :placeholder="t('JABVOX_ANALYTICS.SQL.WIDGET_TITLE')"
            />
          </div>
          <div>
            <label class="mb-1 block text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_ANALYTICS.SQL.TARGET_DASHBOARD') }}
            </label>
            <select v-model="saveForm.dashboardId" :class="controlClass">
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
            <select v-model="saveForm.widgetType" :class="controlClass">
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
            @click="showSaveModal = false"
          >
            {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="
              saving || !saveForm.title.trim() || !saveForm.dashboardId
            "
            @click="saveAsWidget"
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
  </div>
</template>
