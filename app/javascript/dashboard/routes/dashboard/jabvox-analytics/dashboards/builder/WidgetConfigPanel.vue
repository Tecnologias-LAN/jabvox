<script setup>
import { ref, reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsWidgetsStore } from 'dashboard/stores/jabvox/analytics/widgets';
import { useAnalyticsQueryStore } from 'dashboard/stores/jabvox/analytics/query';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsDataTable from '../../data-sources/AnalyticsDataTable.vue';
import ColumnValueFilter from '../../data-sources/ColumnValueFilter.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  widget: { type: Object, default: null },
  dashboardId: { type: [Number, String], required: true },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();
const dsStore = useAnalyticsDataSourcesStore();
const widgetsStore = useAnalyticsWidgetsStore();
const queryStore = useAnalyticsQueryStore();
const capabilities = useAnalyticsCapabilitiesStore();
const { showError } = useAnalyticsError();

const saving = ref(false);
const previewing = ref(false);
const convertingSql = ref(false);
const schemaLoading = ref(false);

const WIDGET_TYPES = [
  { value: 'number', key: 'NUMBER' },
  { value: 'table', key: 'TABLE' },
  { value: 'bar', key: 'BAR' },
  { value: 'line', key: 'LINE' },
  { value: 'pie', key: 'PIE' },
  { value: 'donut', key: 'DONUT' },
];
const FUNCTIONS = ['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'];

// Spec visual: table, columns, aggregations [{fn,column}], filters [{field,values:[]}], groupBy.
const form = reactive({
  titleJabvox: '',
  widgetType: 'table',
  dataSourceId: null,
  table: '',
  aggregations: [{ fn: 'COUNT', column: null }],
  filters: [],
  groupBy: null,
  customSql: false,
  sql: '',
});

const dataSources = computed(() => dsStore.list);
const canUseSql = computed(() => capabilities.canUseCustomSql);

const schema = computed(() => {
  const raw = dsStore.schemaFor(form.dataSourceId);
  if (!raw) return [];
  if (Array.isArray(raw)) return raw;
  return [...(raw.tables || []), ...(raw.views || [])];
});

const tableColumns = computed(() => {
  const node = schema.value.find(item => item.name === form.table);
  return node?.columns || [];
});

const ensureSchema = async id => {
  if (!id || dsStore.schemaFor(id)) return;
  schemaLoading.value = true;
  try {
    await dsStore.fetchSchema(id);
  } catch (error) {
    showError(error);
  } finally {
    schemaLoading.value = false;
  }
};

const resetForm = () => {
  const w = props.widget || {};
  const spec = w.querySpecJabvox || {};
  form.titleJabvox = w.titleJabvox || '';
  form.widgetType = w.widgetTypeJabvox || 'table';
  form.dataSourceId = w.dataSourceId || null;
  form.table = spec.table || '';
  form.aggregations =
    Array.isArray(spec.aggregations) && spec.aggregations.length
      ? spec.aggregations.map(a => ({
          fn: a.fn || a.function || 'COUNT',
          column: a.column ?? null,
        }))
      : [{ fn: 'COUNT', column: null }];
  form.filters = Array.isArray(spec.filters)
    ? spec.filters.map(f => ({
        field: f.field ?? null,
        values: Array.isArray(f.values) ? [...f.values] : [],
      }))
    : [];
  form.groupBy = spec.groupBy ?? spec.group_by ?? null;
  form.customSql = Boolean(w.customSqlJabvox);
  form.sql = w.customSqlJabvox || '';
  queryStore.resetResult();
};

watch(
  () => props.open,
  async isOpen => {
    if (!isOpen) return;
    resetForm();
    if (!dataSources.value.length) {
      await dsStore.fetch().catch(error => showError(error));
    }
    await ensureSchema(form.dataSourceId);
  },
  { immediate: true }
);

const onDataSourceChange = async value => {
  form.dataSourceId = value;
  form.table = '';
  form.aggregations = [{ fn: 'COUNT', column: null }];
  form.filters = [];
  form.groupBy = null;
  await ensureSchema(value);
};

watch(
  () => form.table,
  (next, prev) => {
    if (prev !== undefined && next !== prev) {
      form.aggregations = [{ fn: 'COUNT', column: null }];
      form.filters = [];
      form.groupBy = null;
    }
  }
);

// ── Medidas ──
const addAggregation = () =>
  form.aggregations.push({ fn: 'COUNT', column: null });
const removeAggregation = i => form.aggregations.splice(i, 1);
const updateAgg = (i, key, value) => {
  form.aggregations[i] = { ...form.aggregations[i], [key]: value };
};

// ── Filtros (selección de valores) ──
const addFilter = () => form.filters.push({ field: null, values: [] });
const removeFilter = i => form.filters.splice(i, 1);
const setFilterField = (i, field) => {
  form.filters[i] = { field: field || null, values: [] };
};
const setFilterValues = (i, vals) => {
  form.filters[i] = { ...form.filters[i], values: vals };
};

const fetchColumnValues = params =>
  queryStore.fetchColumnValues(form.dataSourceId, params);

// Spec canónico (snake_case) para backend y para compilar a SQL.
const currentSpec = () => ({
  table: form.table,
  columns: [],
  filters: form.filters.filter(f => f.field && f.values.length),
  aggregations: form.aggregations.filter(a => a.column || a.fn === 'COUNT'),
  group_by: form.groupBy || null,
  date_bucket: null,
});

// ── Conversión bidireccional query ↔ visual ──
const onToggleSql = async checked => {
  form.customSql = checked;
  if (!checked) {
    // visual: aseguramos tener columnas de la tabla para los selectores
    await ensureSchema(form.dataSourceId);
    return;
  }
  // Al activar SQL: convertir la configuración visual actual en SQL editable.
  if (!form.table || !form.dataSourceId) return;
  convertingSql.value = true;
  try {
    form.sql = await queryStore.compileSql(form.dataSourceId, currentSpec());
  } catch (error) {
    showError(error);
  } finally {
    convertingSql.value = false;
  }
};

// ── Previsualización ──
const previewRows = computed(() => queryStore.result.rows);
const previewColumns = computed(() => queryStore.result.columns);
const hasPreview = computed(() => previewColumns.value.length > 0);

const runPreview = async () => {
  if (!form.dataSourceId) return;
  previewing.value = true;
  try {
    if (form.customSql) {
      queryStore.sql = form.sql;
      await queryStore.runSql(form.dataSourceId);
    } else {
      queryStore.setSpec(currentSpec());
      await queryStore.runVisualQuery(form.dataSourceId);
    }
  } catch (error) {
    showError(error);
  } finally {
    previewing.value = false;
  }
};

const handleSave = async () => {
  saving.value = true;
  try {
    const payload = {
      title_jabvox: form.titleJabvox,
      widget_type_jabvox: form.widgetType,
      data_source_id: form.dataSourceId,
    };
    if (form.customSql) {
      payload.custom_sql_jabvox = form.sql;
      payload.query_spec_jabvox = {};
    } else {
      payload.custom_sql_jabvox = null;
      payload.query_spec_jabvox = currentSpec();
    }
    await widgetsStore.updateWidget(
      props.dashboardId,
      props.widget.id,
      payload
    );
    useAlert(t('JABVOX_ANALYTICS.COMMON.SAVE'));
    emit('saved');
  } catch (error) {
    showError(error);
  } finally {
    saving.value = false;
  }
};

const labelClass =
  'mb-1.5 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-n-slate-11';
const controlClass =
  'w-full rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand';
</script>

<template>
  <div>
    <div
      v-if="open && widget"
      class="fixed inset-y-0 right-0 z-50 flex w-full max-w-lg flex-col border-l border-n-weak bg-n-solid-1 shadow-xl"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak px-4 py-3"
      >
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.TITLE') }}
        </h3>
        <button
          type="button"
          class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <div class="flex flex-1 flex-col gap-4 overflow-y-auto p-4">
        <!-- Título -->
        <div>
          <label :class="labelClass">
            {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.WIDGET_TITLE') }}
          </label>
          <input
            v-model="form.titleJabvox"
            type="text"
            :class="controlClass"
            :placeholder="
              t('JABVOX_ANALYTICS.WIDGETS.CONFIG.WIDGET_TITLE_PLACEHOLDER')
            "
          />
        </div>

        <!-- Tipo de widget + fuente -->
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label :class="labelClass">
              {{ t('JABVOX_ANALYTICS.SQL.WIDGET_TYPE') }}
            </label>
            <select v-model="form.widgetType" :class="controlClass">
              <option v-for="w in WIDGET_TYPES" :key="w.value" :value="w.value">
                {{ t(`JABVOX_ANALYTICS.WIDGETS.TYPES.${w.key}`) }}
              </option>
            </select>
          </div>
          <div>
            <label :class="labelClass">
              {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.DATA_SOURCE') }}
            </label>
            <select
              :value="form.dataSourceId"
              :class="controlClass"
              @change="onDataSourceChange(Number($event.target.value) || null)"
            >
              <option :value="null">
                {{ t('JABVOX_ANALYTICS.COMMON.NONE') }}
              </option>
              <option v-for="ds in dataSources" :key="ds.id" :value="ds.id">
                {{ ds.nameJabvox }}
              </option>
            </select>
          </div>
        </div>

        <!-- Toggle SQL / Visual -->
        <label
          v-if="canUseSql"
          class="flex items-center gap-2 rounded-lg bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
        >
          <input
            type="checkbox"
            class="size-4 rounded border-n-weak"
            :checked="form.customSql"
            @change="onToggleSql($event.target.checked)"
          />
          <span class="flex items-center gap-1.5">
            <span class="i-lucide-code size-4 text-n-brand" />
            {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.CUSTOM_SQL') }}
          </span>
          <span
            v-if="convertingSql"
            class="i-lucide-loader-circle ml-auto size-4 animate-spin text-n-slate-10"
          />
        </label>

        <!-- ═══ Editor SQL ═══ -->
        <div v-if="form.customSql && canUseSql">
          <label :class="labelClass">
            <span class="i-lucide-terminal size-3.5 text-n-brand" />
            {{ 'SQL' }}
          </label>
          <textarea
            v-model="form.sql"
            rows="7"
            :class="controlClass"
            class="font-mono text-xs leading-relaxed"
            :placeholder="t('JABVOX_ANALYTICS.WIDGETS.CONFIG.SQL_PLACEHOLDER')"
          />
        </div>

        <!-- ═══ Config visual ═══ -->
        <template v-else>
          <!-- Tabla -->
          <div>
            <label :class="labelClass">
              <span class="i-lucide-table size-3.5 text-n-brand" />
              {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.TABLE') }}
            </label>
            <div
              v-if="schemaLoading"
              class="flex items-center gap-2 py-2 text-sm text-n-slate-10"
            >
              <span class="i-lucide-loader-circle size-4 animate-spin" />
              {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_LOADING_COLUMNS') }}
            </div>
            <select
              v-else
              v-model="form.table"
              :class="controlClass"
              :disabled="!form.dataSourceId"
            >
              <option value="">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
              <option v-for="tbl in schema" :key="tbl.name" :value="tbl.name">
                {{ tbl.name }}
              </option>
            </select>
          </div>

          <template v-if="form.table">
            <!-- Medir -->
            <div>
              <label :class="labelClass">
                <span class="i-lucide-calculator size-3.5 text-n-brand" />
                {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_MEASURE') }}
              </label>
              <div class="flex flex-col gap-2">
                <div
                  v-for="(a, i) in form.aggregations"
                  :key="`a${i}`"
                  class="flex items-center gap-2"
                >
                  <select
                    :value="a.fn"
                    class="w-28 shrink-0 rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                    @change="updateAgg(i, 'fn', $event.target.value)"
                  >
                    <option v-for="fn in FUNCTIONS" :key="fn" :value="fn">
                      {{ fn }}
                    </option>
                  </select>
                  <select
                    :value="a.column"
                    class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                    @change="
                      updateAgg(i, 'column', $event.target.value || null)
                    "
                  >
                    <option :value="null">
                      {{
                        a.fn === 'COUNT'
                          ? t('JABVOX_ANALYTICS.VIEWER.SUMMARY_ALL_ROWS')
                          : t('JABVOX_ANALYTICS.VIEWER.SUMMARY_COLUMN')
                      }}
                    </option>
                    <option
                      v-for="c in tableColumns"
                      :key="c.name"
                      :value="c.name"
                    >
                      {{ c.name }}
                    </option>
                  </select>
                  <button
                    type="button"
                    class="flex size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-9 disabled:opacity-40"
                    :disabled="form.aggregations.length === 1"
                    @click="removeAggregation(i)"
                  >
                    <span class="i-lucide-trash-2 size-4" />
                  </button>
                </div>
                <button
                  type="button"
                  class="inline-flex w-fit items-center gap-1.5 rounded-lg border border-dashed border-n-weak px-2.5 py-1.5 text-xs font-medium text-n-slate-11 hover:border-n-brand hover:text-n-brand"
                  @click="addAggregation"
                >
                  <span class="i-lucide-plus size-3.5" />
                  {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_ADD_MEASURE') }}
                </button>
              </div>
            </div>

            <!-- Agrupar por -->
            <div>
              <label :class="labelClass">
                <span class="i-lucide-layers size-3.5 text-n-brand" />
                {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_GROUP') }}
              </label>
              <select v-model="form.groupBy" :class="controlClass">
                <option :value="null">
                  {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_NO_GROUP') }}
                </option>
                <option v-for="c in tableColumns" :key="c.name" :value="c.name">
                  {{ c.name }}
                </option>
              </select>
            </div>

            <!-- Filtros (selección) -->
            <div>
              <label :class="labelClass">
                <span class="i-lucide-filter size-3.5 text-n-brand" />
                {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.FILTERS') }}
              </label>
              <div class="flex flex-col gap-2">
                <div
                  v-for="(f, i) in form.filters"
                  :key="`f${i}`"
                  class="flex items-center gap-2"
                >
                  <select
                    :value="f.field"
                    class="w-40 shrink-0 rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                    @change="setFilterField(i, $event.target.value)"
                  >
                    <option :value="null">
                      {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_FILTER_TYPE') }}
                    </option>
                    <option
                      v-for="c in tableColumns"
                      :key="c.name"
                      :value="c.name"
                    >
                      {{ c.name }}
                    </option>
                  </select>
                  <div class="min-w-0 flex-1">
                    <ColumnValueFilter
                      v-if="f.field"
                      :key="f.field"
                      :column="f.field"
                      :table="form.table"
                      :model-value="f.values"
                      :fetcher="fetchColumnValues"
                      @update:model-value="vals => setFilterValues(i, vals)"
                    />
                    <span
                      v-else
                      class="block px-1 text-xs italic text-n-slate-10"
                    >
                      {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_PICK_VALUES') }}
                    </span>
                  </div>
                  <button
                    type="button"
                    class="flex size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-9"
                    @click="removeFilter(i)"
                  >
                    <span class="i-lucide-trash-2 size-4" />
                  </button>
                </div>
                <button
                  type="button"
                  class="inline-flex w-fit items-center gap-1.5 rounded-lg border border-dashed border-n-weak px-2.5 py-1.5 text-xs font-medium text-n-slate-11 hover:border-n-brand hover:text-n-brand"
                  @click="addFilter"
                >
                  <span class="i-lucide-plus size-3.5" />
                  {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_ADD_FILTER') }}
                </button>
              </div>
            </div>
          </template>
        </template>

        <!-- Previsualización -->
        <div v-if="form.dataSourceId" class="mt-1">
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="previewing"
            @click="runPreview"
          >
            <span
              v-if="previewing"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            <span v-else class="i-lucide-eye size-4" />
            {{ t('JABVOX_ANALYTICS.WIDGETS.CONFIG.PREVIEW') }}
          </button>
          <div v-if="hasPreview" class="mt-3">
            <AnalyticsDataTable
              :rows="previewRows"
              :columns="previewColumns"
              :loading="previewing"
            />
          </div>
        </div>
      </div>

      <div
        class="flex items-center justify-end gap-3 border-t border-n-weak px-4 py-3"
      >
        <button
          type="button"
          class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
          @click="emit('close')"
        >
          {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="saving"
          @click="handleSave"
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
