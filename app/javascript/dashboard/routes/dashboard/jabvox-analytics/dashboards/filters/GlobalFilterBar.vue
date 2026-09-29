<script setup>
import { reactive, ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsWidgetsStore } from 'dashboard/stores/jabvox/analytics/widgets';

// Barra de filtros del tablero.
//
// Antes traía tres controles FIJOS —"Fecha desde", "Fecha hasta" y un buscador por clave
// escrita a mano— que no tenían relación con los datos del tablero: había que adivinar el
// nombre de la columna y las fechas se aplicaban existiera o no una columna de fecha.
//
// Ahora los filtros se DERIVAN de las tablas que usan los widgets del tablero: se leen sus
// columnas del esquema de la fuente y se ofrece el control que corresponde a cada tipo
// (fecha → rango, texto → contiene, número → igual/mayor/menor, booleano → sí/no).
const props = defineProps({
  dashboardId: { type: [Number, String], required: true },
});

const emit = defineEmits(['apply']);

const { t } = useI18n();
const store = useAnalyticsDashboardsStore();
const dsStore = useAnalyticsDataSourcesStore();
const widgetsStore = useAnalyticsWidgetsStore();

// Valor actual de cada filtro, por clave "tabla.columna".
const local = reactive({ ...(store.globalFilters.dynamic || {}) });
const loadingSchema = ref(false);

watch(
  () => store.globalFilters,
  filters => {
    Object.keys(local).forEach(k => delete local[k]);
    Object.assign(local, filters.dynamic || {});
  }
);

const widgets = computed(
  () => widgetsStore.widgetsByDashboard[Number(props.dashboardId)] || []
);

// Tablas que el tablero consulta de verdad, con su fuente. Un widget de SQL libre o de
// reporte cruzado no declara tabla, así que no aporta filtros: no hay esquema que leer.
const usedTables = computed(() => {
  const seen = new Map();
  widgets.value.forEach(w => {
    const spec = w.querySpecJabvox || w.query_spec_jabvox || {};
    const table = spec.table;
    const dsId = w.dataSourceId || w.data_source_id;
    if (!table || !dsId) return;
    seen.set(`${dsId}:${table}`, { dsId, table });
  });
  return [...seen.values()];
});

// Tipo de control según el tipo de la columna en la base.
const controlFor = rawType => {
  const type = String(rawType || '').toLowerCase();
  if (/(timestamp|datetime|date)/.test(type)) return 'date';
  if (/(bool)/.test(type)) return 'boolean';
  if (/(int|numeric|decimal|real|double|float|money)/.test(type))
    return 'number';
  return 'text';
};

// Un filtro por columna de las tablas en uso. Se limita a un número razonable de columnas
// por tabla para que una tabla ancha no genere una barra inmanejable.
const MAX_COLUMNS_PER_TABLE = 12;

const availableFilters = computed(() => {
  const out = [];
  usedTables.value.forEach(({ dsId, table }) => {
    const raw = dsStore.schemaFor(dsId);
    if (!raw) return;
    const nodes = Array.isArray(raw) ? raw : [...(raw.tables || [])];
    const node = nodes.find(n => n.name === table);
    if (!node) return;
    (node.columns || []).slice(0, MAX_COLUMNS_PER_TABLE).forEach(col => {
      out.push({
        key: `${table}.${col.name}`,
        table,
        column: col.name,
        control: controlFor(col.type),
      });
    });
  });
  return out;
});

const hasFilters = computed(() => availableFilters.value.length > 0);

// Solo se muestran los filtros que el usuario ha añadido, para no llenar la barra con
// todas las columnas de golpe.
const activeKeys = ref([]);
const pickerKey = ref('');

watch(
  availableFilters,
  list => {
    // Al cambiar el tablero se descartan los filtros que ya no existen.
    const valid = new Set(list.map(f => f.key));
    activeKeys.value = activeKeys.value.filter(k => valid.has(k));
    Object.keys(local).forEach(k => {
      if (!valid.has(k)) delete local[k];
    });
  },
  { immediate: true }
);

const activeFilters = computed(() =>
  activeKeys.value
    .map(k => availableFilters.value.find(f => f.key === k))
    .filter(Boolean)
);

const remainingFilters = computed(() =>
  availableFilters.value.filter(f => !activeKeys.value.includes(f.key))
);

const addFilter = () => {
  const key = pickerKey.value;
  if (!key || activeKeys.value.includes(key)) return;
  activeKeys.value = [...activeKeys.value, key];
  pickerKey.value = '';
};

const removeFilter = key => {
  activeKeys.value = activeKeys.value.filter(k => k !== key);
  delete local[key];
};

// Carga el esquema de cada fuente usada, que es de donde salen las columnas.
const ensureSchemas = async () => {
  const ids = [...new Set(usedTables.value.map(u => u.dsId))];
  const pending = ids.filter(id => !dsStore.schemaFor(id));
  if (!pending.length) return;
  loadingSchema.value = true;
  try {
    await Promise.allSettled(pending.map(id => dsStore.fetchSchema(id)));
  } finally {
    loadingSchema.value = false;
  }
};

onMounted(ensureSchemas);
watch(usedTables, ensureSchemas);

const apply = () => {
  // Las claves vacías no se envían: un filtro sin valor no debe recortar nada.
  const dynamic = {};
  Object.entries(local).forEach(([k, v]) => {
    if (v !== '' && v !== null && v !== undefined) dynamic[k] = v;
  });
  store.setGlobalFilters({ dateFrom: null, dateTo: null, dynamic });
  emit('apply');
};

const clear = () => {
  Object.keys(local).forEach(k => delete local[k]);
  activeKeys.value = [];
  apply();
};

const labelClass = 'text-xs font-medium text-n-slate-11';
const inputClass =
  'rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div
    class="mb-4 rounded-lg border border-n-weak bg-n-solid-1 p-3"
    :class="{ 'animate-pulse': loadingSchema }"
  >
    <!-- Sin tablas declaradas (todo SQL libre o cruces) no hay columnas que ofrecer. -->
    <p
      v-if="!hasFilters"
      class="flex items-center gap-1.5 text-xs text-n-slate-10"
    >
      <span class="i-lucide-filter-x size-3.5 shrink-0" />
      {{ t('JABVOX_ANALYTICS.FILTERS.NO_FILTERS_AVAILABLE') }}
    </p>

    <template v-else>
      <div class="flex flex-wrap items-end gap-3">
        <div
          v-for="filter in activeFilters"
          :key="filter.key"
          class="flex min-w-0 flex-col gap-1"
        >
          <span :class="labelClass" class="flex items-center gap-1">
            {{ filter.column }}
            <span class="text-n-slate-9">· {{ filter.table }}</span>
            <button
              type="button"
              class="text-n-slate-10 hover:text-n-ruby-11"
              :aria-label="t('JABVOX_ANALYTICS.FILTERS.REMOVE')"
              @click="removeFilter(filter.key)"
            >
              <span class="i-lucide-x size-3" />
            </button>
          </span>

          <input
            v-if="filter.control === 'date'"
            v-model="local[filter.key]"
            type="date"
            :class="inputClass"
          />
          <input
            v-else-if="filter.control === 'number'"
            v-model="local[filter.key]"
            type="number"
            :class="inputClass"
            :placeholder="t('JABVOX_ANALYTICS.FILTERS.VALUE')"
          />
          <select
            v-else-if="filter.control === 'boolean'"
            v-model="local[filter.key]"
            :class="inputClass"
          >
            <option value="">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
            <option value="true">
              {{ t('JABVOX_ANALYTICS.FILTERS.YES') }}
            </option>
            <option value="false">
              {{ t('JABVOX_ANALYTICS.FILTERS.NO') }}
            </option>
          </select>
          <input
            v-else
            v-model="local[filter.key]"
            type="text"
            :class="inputClass"
            :placeholder="t('JABVOX_ANALYTICS.FILTERS.CONTAINS')"
          />
        </div>

        <!-- Añadir un filtro de los disponibles -->
        <div v-if="remainingFilters.length" class="flex flex-col gap-1">
          <span :class="labelClass">
            {{ t('JABVOX_ANALYTICS.FILTERS.ADD_FILTER') }}
          </span>
          <select v-model="pickerKey" :class="inputClass" @change="addFilter">
            <option value="">
              {{ t('JABVOX_ANALYTICS.FILTERS.PICK_COLUMN') }}
            </option>
            <option v-for="f in remainingFilters" :key="f.key" :value="f.key">
              {{ f.table }}.{{ f.column }}
            </option>
          </select>
        </div>

        <div class="ml-auto flex items-center gap-2">
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
            @click="clear"
          >
            {{ t('JABVOX_ANALYTICS.FILTERS.CLEAR') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white"
            @click="apply"
          >
            {{ t('JABVOX_ANALYTICS.FILTERS.APPLY') }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
