<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useDebounceFn } from '@vueuse/core';
import { useAnalyticsQueryStore } from 'dashboard/stores/jabvox/analytics/query';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsDataTable from './AnalyticsDataTable.vue';
import ColumnValueFilter from './ColumnValueFilter.vue';

const { t } = useI18n();
const route = useRoute();
const store = useAnalyticsQueryStore();
const dsStore = useAnalyticsDataSourcesStore();
const { showError } = useAnalyticsError();

const PER_PAGE_OPTIONS = [25, 50, 100, 250];

const dataSourceId = computed(() => route.params.dataSourceId);
const table = computed(() => route.query.table);

const search = ref('');
const perPage = ref(100);
const page = ref(1);
const sort = ref(null);
// Filtros seleccionables por columna (multi-valor): { nombreColumna: [v1, v2, ...] }
const columnFilters = ref({});

// Sólo los filtros con al menos un valor (arrays vacíos se omiten).
const activeFilters = () => {
  const out = {};
  Object.entries(columnFilters.value).forEach(([k, v]) => {
    if (Array.isArray(v) && v.length) out[k] = v;
  });
  return Object.keys(out).length ? out : undefined;
};

const load = async () => {
  try {
    await store.previewTable(dataSourceId.value, {
      table: table.value,
      page: page.value,
      perPage: perPage.value,
      sort: sort.value,
      search: search.value,
      filters: activeFilters(),
    });
  } catch (error) {
    showError(error);
  }
};

const onColumnFilter = (column, values) => {
  columnFilters.value = { ...columnFilters.value, [column]: values };
  page.value = 1;
  load();
};

const activeFilterCount = computed(
  () =>
    Object.values(columnFilters.value).filter(v => Array.isArray(v) && v.length)
      .length
);

// Solo las columnas con filtro activo, para los "chips" de arriba.
const activeFilterChips = computed(() => {
  const out = {};
  Object.entries(columnFilters.value).forEach(([k, v]) => {
    if (Array.isArray(v) && v.length) out[k] = v;
  });
  return out;
});

const clearFilters = () => {
  columnFilters.value = {};
  page.value = 1;
  load();
};

const clearSearch = () => {
  search.value = '';
  page.value = 1;
  load();
};

// Fetcher que el ColumnValueFilter usa para traer valores distintos de la columna.
const fetchColumnValues = params =>
  store.fetchColumnValues(dataSourceId.value, params);

// ─── Modo Resumen (Summarize estilo Metabase) ───
const mode = ref('data'); // 'data' | 'summary'
const FUNCTIONS = ['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'];
// Medidas: [{ fn, column }]. Filtros por valores (multi-selección): [{ field, values:[] }].
const sumAggregations = ref([{ fn: 'COUNT', column: null }]);
const sumFilters = ref([]);
const sumGroupBy = ref(null); // una sola columna de agrupación
const summaryRunning = ref(false);
const summaryRan = ref(false);

const tableColumns = computed(() => {
  const raw = dsStore.schemaFor(dataSourceId.value);
  const list = Array.isArray(raw)
    ? raw
    : [...(raw?.tables || []), ...(raw?.views || [])];
  return list.find(item => item.name === table.value)?.columns || [];
});

const addFilter = () => sumFilters.value.push({ field: null, values: [] });
const removeFilter = i => sumFilters.value.splice(i, 1);
const setFilterValues = (i, vals) => {
  sumFilters.value[i] = { ...sumFilters.value[i], values: vals };
};
const setFilterField = (i, field) => {
  sumFilters.value[i] = { field: field || null, values: [] };
};
const addAggregation = () =>
  sumAggregations.value.push({ fn: 'COUNT', column: null });
const removeAggregation = i => sumAggregations.value.splice(i, 1);
const updateAgg = (i, key, value) => {
  sumAggregations.value[i] = { ...sumAggregations.value[i], [key]: value };
};

// ¿Se puede ejecutar? Al menos una medida válida (COUNT siempre lo es).
const canRunSummary = computed(() =>
  sumAggregations.value.some(a => a.fn === 'COUNT' || a.column)
);

const runSummary = async () => {
  summaryRunning.value = true;
  store.setSpec({
    table: table.value,
    columns: [],
    filters: sumFilters.value.filter(f => f.field && f.values.length),
    aggregations: sumAggregations.value.filter(
      a => a.column || a.fn === 'COUNT'
    ),
    group_by: sumGroupBy.value,
    date_bucket: null,
  });
  try {
    await store.runVisualQuery(dataSourceId.value);
    summaryRan.value = true;
  } catch (error) {
    showError(error);
  } finally {
    summaryRunning.value = false;
  }
};

const schemaLoading = ref(false);
const switchMode = async newMode => {
  mode.value = newMode;
  if (newMode === 'data') {
    load();
    return;
  }
  // Al entrar a Resumen aseguramos tener las columnas para los selectores.
  if (!tableColumns.value.length) {
    schemaLoading.value = true;
    try {
      await dsStore.fetchSchema(dataSourceId.value);
    } catch (error) {
      showError(error);
    } finally {
      schemaLoading.value = false;
    }
  }
};

const rows = computed(() => store.result.rows);
const columns = computed(() => store.result.columns);
const total = computed(() => store.result.total);

// ── Presentación de la tabla de resultados del resumen ──
const summaryColumns = computed(() =>
  columns.value.map(c => (typeof c === 'string' ? c : c.name))
);

const cellValue = (row, index) => {
  const raw = Array.isArray(row)
    ? row[index]
    : row?.[summaryColumns.value[index]];
  return raw === null || raw === undefined ? '—' : raw;
};

// Formatea números con separador de miles y hasta 2 decimales; deja el texto intacto.
const formatNumber = value => {
  if (value === '—' || value === null || value === undefined) return '—';
  const num = Number(value);
  if (Number.isNaN(num)) return value;
  return num.toLocaleString('es-CO', { maximumFractionDigits: 2 });
};
const loading = computed(
  () =>
    store.uiFlags.previewing || store.uiFlags.running || summaryRunning.value
);

const totalPages = computed(() =>
  perPage.value ? Math.max(1, Math.ceil(total.value / perPage.value)) : 1
);
const rowOffset = computed(() => (page.value - 1) * perPage.value);

const debouncedSearch = useDebounceFn(() => {
  page.value = 1;
  load();
}, 400);

const onSearchInput = () => debouncedSearch();

const onPerPageChange = value => {
  perPage.value = Number(value);
  page.value = 1;
  load();
};

const changePage = delta => {
  const next = page.value + delta;
  if (next < 1 || next > totalPages.value) return;
  page.value = next;
  load();
};

onMounted(() => {
  load();
  dsStore.fetchSchema(dataSourceId.value).catch(() => {});
});
</script>

<template>
  <div>
    <AnalyticsPageHeader :title="table || t('JABVOX_ANALYTICS.VIEWER.TITLE')" />

    <!-- Toggle Datos / Resumen -->
    <div class="mb-4 inline-flex rounded-lg bg-n-alpha-1 p-1">
      <button
        type="button"
        class="flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors"
        :class="
          mode === 'data'
            ? 'bg-n-solid-1 text-n-brand shadow-sm'
            : 'text-n-slate-10 hover:text-n-slate-12'
        "
        @click="switchMode('data')"
      >
        <span class="i-lucide-table-2 size-4" />
        {{ t('JABVOX_ANALYTICS.VIEWER.TAB_DATA') }}
      </button>
      <button
        type="button"
        class="flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors"
        :class="
          mode === 'summary'
            ? 'bg-n-solid-1 text-n-brand shadow-sm'
            : 'text-n-slate-10 hover:text-n-slate-12'
        "
        @click="switchMode('summary')"
      >
        <span class="i-lucide-sigma size-4" />
        {{ t('JABVOX_ANALYTICS.VIEWER.TAB_SUMMARY') }}
      </button>
    </div>

    <!-- ═══════════ Panel de Resumen (compacto) ═══════════ -->
    <div
      v-if="mode === 'summary'"
      class="mb-4 overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-sm"
    >
      <div
        class="flex flex-wrap items-center gap-x-2 gap-y-1 border-b border-n-weak bg-n-alpha-1 px-4 py-2.5"
      >
        <span class="i-lucide-sigma size-4 text-n-brand" />
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_TITLE') }}
        </h3>
        <span class="text-xs text-n-slate-10">
          {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_HINT') }}
        </span>
      </div>

      <!-- Cargando columnas de la tabla -->
      <div
        v-if="schemaLoading || !tableColumns.length"
        class="flex items-center gap-2 px-4 py-8 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-circle size-4 animate-spin" />
        {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_LOADING_COLUMNS') }}
      </div>

      <div v-else class="flex flex-col gap-4 p-4">
        <!-- Medir -->
        <section>
          <div class="mb-1.5 flex items-center gap-2">
            <span class="i-lucide-calculator size-4 text-n-brand" />
            <span
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-11"
            >
              {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_MEASURE') }}
            </span>
          </div>
          <div class="flex flex-col gap-2">
            <div
              v-for="(a, i) in sumAggregations"
              :key="`a${i}`"
              class="flex items-center gap-2"
            >
              <select
                :value="a.fn"
                class="w-28 shrink-0 rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                @change="updateAgg(i, 'fn', $event.target.value)"
              >
                <option v-for="fn in FUNCTIONS" :key="fn" :value="fn">
                  {{ fn }}
                </option>
              </select>
              <select
                :value="a.column"
                class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                @change="updateAgg(i, 'column', $event.target.value || null)"
              >
                <option :value="null">
                  {{
                    a.fn === 'COUNT'
                      ? t('JABVOX_ANALYTICS.VIEWER.SUMMARY_ALL_ROWS')
                      : t('JABVOX_ANALYTICS.VIEWER.SUMMARY_COLUMN')
                  }}
                </option>
                <option v-for="c in tableColumns" :key="c.name" :value="c.name">
                  {{ c.name }}
                </option>
              </select>
              <button
                type="button"
                class="flex size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-9"
                :disabled="sumAggregations.length === 1"
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
        </section>

        <!-- Agrupar por (una sola columna) -->
        <section>
          <div class="mb-1.5 flex items-center gap-2">
            <span class="i-lucide-layers size-4 text-n-brand" />
            <span
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-11"
            >
              {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_GROUP') }}
            </span>
          </div>
          <select
            :value="sumGroupBy"
            class="w-full max-w-xs rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            @change="sumGroupBy = $event.target.value || null"
          >
            <option :value="null">
              {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_NO_GROUP') }}
            </option>
            <option v-for="c in tableColumns" :key="c.name" :value="c.name">
              {{ c.name }}
            </option>
          </select>
        </section>

        <!-- Filtros (selección de valores, no se escribe) -->
        <section>
          <div class="mb-1.5 flex items-center gap-2">
            <span class="i-lucide-filter size-4 text-n-brand" />
            <span
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-11"
            >
              {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.FILTERS') }}
            </span>
          </div>
          <div class="flex flex-col gap-2">
            <div
              v-for="(f, i) in sumFilters"
              :key="`f${i}`"
              class="flex items-center gap-2"
            >
              <select
                :value="f.field"
                class="w-44 shrink-0 rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                @change="setFilterField(i, $event.target.value)"
              >
                <option :value="null">
                  {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_FILTER_TYPE') }}
                </option>
                <option v-for="c in tableColumns" :key="c.name" :value="c.name">
                  {{ c.name }}
                </option>
              </select>
              <div class="min-w-0 flex-1">
                <ColumnValueFilter
                  v-if="f.field"
                  :key="f.field"
                  :column="f.field"
                  :table="table"
                  :model-value="f.values"
                  :fetcher="fetchColumnValues"
                  @update:model-value="vals => setFilterValues(i, vals)"
                />
                <span v-else class="block px-1 text-xs italic text-n-slate-10">
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
        </section>
      </div>

      <div
        class="flex items-center justify-between gap-3 border-t border-n-weak bg-n-alpha-1 px-4 py-2.5"
      >
        <span class="text-xs text-n-slate-10">
          {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_RUN_HINT') }}
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="summaryRunning || !canRunSummary"
          @click="runSummary"
        >
          <span
            v-if="summaryRunning"
            class="i-lucide-loader-circle size-4 animate-spin"
          />
          <span v-else class="i-lucide-play size-4" />
          {{ t('JABVOX_ANALYTICS.VIEWER.RUN_SUMMARY') }}
        </button>
      </div>
    </div>

    <!-- Resultado del resumen (tabla dedicada: dimensión destacada + métricas alineadas) -->
    <div v-if="mode === 'summary'">
      <div
        v-if="summaryRan"
        class="mb-2 flex items-center gap-2 text-sm text-n-slate-11"
      >
        <span class="i-lucide-sparkles size-4 text-n-brand" />
        {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_RESULT', { total: total }) }}
      </div>

      <div
        v-if="loading"
        class="rounded-xl border border-n-weak bg-n-solid-1 px-4 py-12 text-center text-n-slate-11 shadow-sm"
      >
        <span
          class="i-lucide-loader-circle mr-2 inline-block size-5 animate-spin"
        />
        {{ t('JABVOX_ANALYTICS.COMMON.LOADING') }}
      </div>

      <div
        v-else-if="!rows.length"
        class="rounded-xl border border-dashed border-n-weak bg-n-solid-1 px-4 py-12 text-center text-n-slate-10 shadow-sm"
      >
        <span class="i-lucide-bar-chart-3 mb-2 block text-3xl opacity-50" />
        {{ t('JABVOX_ANALYTICS.VIEWER.SUMMARY_EMPTY') }}
      </div>

      <div
        v-else
        class="overflow-x-auto rounded-xl border border-n-weak shadow-sm"
      >
        <table class="w-full border-collapse text-sm">
          <thead>
            <tr class="bg-n-alpha-2 text-left">
              <th
                class="w-14 border-b border-n-weak px-3 py-3 text-right text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ '#' }}
              </th>
              <th
                v-for="(col, ci) in summaryColumns"
                :key="col"
                class="border-b border-n-weak px-4 py-3 text-xs font-semibold uppercase tracking-wide"
                :class="[
                  ci === 0
                    ? 'text-left text-n-slate-12'
                    : 'text-right text-n-brand',
                ]"
              >
                <span class="inline-flex items-center gap-1">
                  <span
                    v-if="ci !== 0"
                    class="i-lucide-hash size-3 opacity-60"
                  />
                  {{ col }}
                </span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, ri) in rows"
              :key="ri"
              class="border-b border-n-weak/60 last:border-b-0 odd:bg-n-alpha-1/40 hover:bg-n-brand/5"
            >
              <td
                class="px-3 py-2.5 text-right text-xs tabular-nums text-n-slate-10"
              >
                {{ ri + 1 }}
              </td>
              <td
                v-for="(col, ci) in summaryColumns"
                :key="col"
                class="px-4 py-2.5"
                :class="[
                  ci === 0
                    ? 'font-medium text-n-slate-12'
                    : 'text-right tabular-nums text-n-slate-12',
                ]"
              >
                {{
                  ci === 0
                    ? cellValue(row, ci)
                    : formatNumber(cellValue(row, ci))
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- ═══════════ Modo Datos ═══════════ -->
    <template v-if="mode === 'data'">
      <!-- Toolbar -->
      <div class="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center">
        <!-- Search: busca en TODAS las columnas, dentro de las filas ya filtradas -->
        <div class="relative min-w-0 flex-1">
          <span
            class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
          />
          <input
            v-model="search"
            type="text"
            class="block w-full rounded-lg border border-n-weak bg-n-solid-1 py-2.5 pl-10 pr-9 text-sm text-n-slate-12 shadow-sm outline-none transition-colors focus:border-n-brand focus:ring-1 focus:ring-n-brand/30"
            :placeholder="
              activeFilterCount
                ? t('JABVOX_ANALYTICS.VIEWER.SEARCH_WITHIN')
                : t('JABVOX_ANALYTICS.VIEWER.SEARCH_ALL')
            "
            @input="onSearchInput"
          />
          <button
            v-if="search"
            type="button"
            class="absolute right-2.5 top-1/2 -translate-y-1/2 rounded p-0.5 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
            @click="clearSearch"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
        <label class="flex shrink-0 items-center gap-2 text-sm text-n-slate-11">
          {{ t('JABVOX_ANALYTICS.VIEWER.ROWS_PER_PAGE') }}
          <select
            :value="perPage"
            class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12 shadow-sm outline-none"
            @change="onPerPageChange($event.target.value)"
          >
            <option v-for="opt in PER_PAGE_OPTIONS" :key="opt" :value="opt">
              {{ opt }}
            </option>
          </select>
        </label>
      </div>

      <!-- Chips de filtros activos -->
      <div
        v-if="activeFilterCount"
        class="mb-3 flex flex-wrap items-center gap-2"
      >
        <span class="text-xs font-medium text-n-slate-10">
          {{ t('JABVOX_ANALYTICS.VIEWER.ACTIVE_FILTERS') }}
        </span>
        <span
          v-for="(vals, col) in activeFilterChips"
          :key="col"
          class="inline-flex items-center gap-1.5 rounded-full bg-n-brand/10 py-1 pl-2.5 pr-1 text-xs font-medium text-n-brand"
        >
          <span class="max-w-48 truncate">
            <span class="font-semibold">{{ col }}</span>
            {{ ` = ${vals.join(', ')}` }}
          </span>
          <button
            type="button"
            class="flex size-4 items-center justify-center rounded-full hover:bg-n-brand/20"
            @click="onColumnFilter(col, [])"
          >
            <span class="i-lucide-x size-3" />
          </button>
        </span>
        <button
          type="button"
          class="inline-flex items-center gap-1 text-xs text-n-slate-10 hover:text-n-slate-12"
          @click="clearFilters"
        >
          <span class="i-lucide-filter-x size-3.5" />
          {{ t('JABVOX_ANALYTICS.VIEWER.CLEAR_ALL') }}
        </button>
      </div>

      <div class="mb-2 flex items-center gap-2 text-sm text-n-slate-11">
        <span class="i-lucide-list size-4 text-n-slate-10" />
        {{
          t('JABVOX_ANALYTICS.VIEWER.ROW_SUMMARY', {
            shown: rows.length,
            total: total,
          })
        }}
      </div>

      <AnalyticsDataTable
        :rows="rows"
        :columns="columns"
        :loading="loading"
        show-row-numbers
        :row-offset="rowOffset"
      >
        <template #filters="{ column }">
          <ColumnValueFilter
            :column="column"
            :table="table"
            :model-value="columnFilters[column] ?? []"
            :fetcher="fetchColumnValues"
            @update:model-value="vals => onColumnFilter(column, vals)"
          />
        </template>
      </AnalyticsDataTable>

      <!-- Paginación -->
      <div
        class="mt-4 flex items-center justify-center gap-4 text-sm text-n-slate-11"
      >
        <button
          type="button"
          class="rounded-lg bg-n-alpha-2 px-3 py-1.5 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="page <= 1 || loading"
          @click="changePage(-1)"
        >
          <span class="i-lucide-chevron-left size-4" />
        </button>
        <span>{{
          t('JABVOX_ANALYTICS.VIEWER.PAGE_OF', { page, total: totalPages })
        }}</span>
        <button
          type="button"
          class="rounded-lg bg-n-alpha-2 px-3 py-1.5 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="page >= totalPages || loading"
          @click="changePage(1)"
        >
          <span class="i-lucide-chevron-right size-4" />
        </button>
      </div>
    </template>
  </div>
</template>
