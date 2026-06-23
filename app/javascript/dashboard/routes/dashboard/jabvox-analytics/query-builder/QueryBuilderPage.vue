<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsQueryStore } from 'dashboard/stores/jabvox/analytics/query';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsDataTable from '../data-sources/AnalyticsDataTable.vue';
import QbTablePicker from './QbTablePicker.vue';
import QbColumnPicker from './QbColumnPicker.vue';
import QbFilterRow from './QbFilterRow.vue';
import QbAggregations from './QbAggregations.vue';
import QbGroupBy from './QbGroupBy.vue';

const { t } = useI18n();
const dsStore = useAnalyticsDataSourcesStore();
const queryStore = useAnalyticsQueryStore();
const { showError } = useAnalyticsError();

const selectedDsId = ref(null);
const selectedTable = ref(null);
const selectedColumns = ref([]);
const filters = ref([]);
const aggregations = ref([]);
const groupBy = ref(null);
const dateBucket = ref(null);

const dataSources = computed(() => dsStore.list);

const schema = computed(() => {
  const raw = dsStore.schemaFor(selectedDsId.value);
  if (!raw) return [];
  if (Array.isArray(raw)) return raw;
  const tables = (raw.tables || []).map(item => ({ ...item, type: 'table' }));
  const views = (raw.views || []).map(item => ({ ...item, type: 'view' }));
  return [...tables, ...views];
});

const tableColumns = computed(() => {
  const node = schema.value.find(item => item.name === selectedTable.value);
  return node?.columns || [];
});

const rows = computed(() => queryStore.result.rows);
const resultColumns = computed(() => queryStore.result.columns);
const running = computed(() => queryStore.uiFlags.running);

const onDataSourceChange = async value => {
  selectedDsId.value = value;
  selectedTable.value = null;
  selectedColumns.value = [];
  filters.value = [];
  aggregations.value = [];
  groupBy.value = null;
  dateBucket.value = null;
  queryStore.resetResult();
  if (!value) return;
  try {
    await dsStore.fetchSchema(value);
  } catch (error) {
    showError(error);
  }
};

watch(selectedTable, () => {
  selectedColumns.value = [];
  filters.value = [];
  aggregations.value = [];
  groupBy.value = null;
});

const addFilter = () => {
  // Default operator must match QbFilterRow's options / backend OPERATOR_SQL ('eq', not '=').
  filters.value.push({ field: null, operator: 'eq', value: '' });
};

const removeFilter = index => {
  filters.value.splice(index, 1);
};

const addAggregation = () => {
  aggregations.value.push({ fn: 'COUNT', column: null });
};

const removeAggregation = index => {
  aggregations.value.splice(index, 1);
};

const canRun = computed(() =>
  Boolean(selectedDsId.value && selectedTable.value)
);

const runQuery = async () => {
  if (!canRun.value) return;
  queryStore.setSpec({
    table: selectedTable.value,
    columns: selectedColumns.value,
    filters: filters.value.filter(f => f.field),
    aggregations: aggregations.value.filter(a => a.column || a.fn === 'COUNT'),
    groupBy: groupBy.value,
    dateBucket: dateBucket.value,
  });
  try {
    await queryStore.runVisualQuery(selectedDsId.value);
  } catch (error) {
    showError(error);
  }
};

onMounted(() => {
  dsStore.fetch().catch(error => showError(error));
});

const controlClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
const sectionClass = 'rounded-lg border border-n-weak bg-n-solid-1 p-4';
</script>

<template>
  <div>
    <AnalyticsPageHeader :title="t('JABVOX_ANALYTICS.QUERY_BUILDER.TITLE')" />

    <!-- Data source selector -->
    <div class="mb-4 max-w-sm">
      <label class="mb-1 block text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.DATA_SOURCE') }}
      </label>
      <select
        :value="selectedDsId"
        :class="controlClass"
        @change="onDataSourceChange(Number($event.target.value) || null)"
      >
        <option :value="null">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
        <option v-for="ds in dataSources" :key="ds.id" :value="ds.id">
          {{ ds.nameJabvox }}
        </option>
      </select>
    </div>

    <template v-if="selectedDsId">
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div :class="sectionClass">
          <QbTablePicker v-model="selectedTable" :tables="schema" />
        </div>
        <div :class="sectionClass">
          <QbColumnPicker v-model="selectedColumns" :columns="tableColumns" />
        </div>
      </div>

      <template v-if="selectedTable">
        <!-- Filters -->
        <div :class="sectionClass" class="mt-4">
          <div class="mb-2 flex items-center justify-between">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.FILTERS') }}
            </span>
            <button
              type="button"
              class="inline-flex items-center gap-1.5 rounded-lg bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-12"
              @click="addFilter"
            >
              <span class="i-lucide-plus size-4" />
            </button>
          </div>
          <div class="flex flex-col gap-2">
            <QbFilterRow
              v-for="(filter, index) in filters"
              :key="index"
              v-model="filters[index]"
              :columns="tableColumns"
              @remove="removeFilter(index)"
            />
            <p v-if="!filters.length" class="text-sm text-n-slate-10">
              {{ t('JABVOX_ANALYTICS.COMMON.NONE') }}
            </p>
          </div>
        </div>

        <!-- Aggregations -->
        <div :class="sectionClass" class="mt-4">
          <div class="mb-2 flex items-center justify-between">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.AGGREGATIONS') }}
            </span>
            <button
              type="button"
              class="inline-flex items-center gap-1.5 rounded-lg bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-12"
              @click="addAggregation"
            >
              <span class="i-lucide-plus size-4" />
            </button>
          </div>
          <div class="flex flex-col gap-2">
            <QbAggregations
              v-for="(agg, index) in aggregations"
              :key="index"
              v-model="aggregations[index]"
              :columns="tableColumns"
              @remove="removeAggregation(index)"
            />
            <p v-if="!aggregations.length" class="text-sm text-n-slate-10">
              {{ t('JABVOX_ANALYTICS.COMMON.NONE') }}
            </p>
          </div>
        </div>

        <!-- Group by -->
        <div :class="sectionClass" class="mt-4">
          <QbGroupBy
            v-model:group-by="groupBy"
            v-model:date-bucket="dateBucket"
            :columns="tableColumns"
          />
        </div>

        <div class="mt-4 flex justify-end">
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!canRun || running"
            @click="runQuery"
          >
            <span
              v-if="running"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            <span v-else class="i-lucide-play size-4" />
            {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.RUN') }}
          </button>
        </div>

        <div class="mt-4">
          <AnalyticsDataTable
            :rows="rows"
            :columns="resultColumns"
            :loading="running"
          />
        </div>
      </template>
    </template>
  </div>
</template>
