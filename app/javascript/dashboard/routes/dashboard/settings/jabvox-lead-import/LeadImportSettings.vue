<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { leadSourcesAPI } from 'dashboard/api/jabvox/leadImport';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();

const apiError = (e, fallback) => e?.response?.data?.error || t(fallback);

// ---------- State ----------
const sources = ref([]);
const editing = ref(null); // the source being created/edited (null = list view)
const testResult = ref(null);
const testing = ref(false);

// Mapping workspace (when a source is opened for mapping)
const mapping = ref(null); // { source, tables, columns, leadFields, table, externalIdColumn, map }
const loadingSchema = ref(false);
const syncingId = ref(null);
const confirmDialog = ref(null);
let pollTimer = null;

const engineOptions = computed(() => [
  { value: 'postgresql', label: 'PostgreSQL' },
  { value: 'mysql', label: 'MySQL' },
  { value: 'mariadb', label: 'MariaDB' },
]);

const fieldTypeOptions = computed(() => [
  { value: 'text', label: t('JABVOX_LEAD_IMPORT.FIELD_TYPES.TEXT') },
  { value: 'integer', label: t('JABVOX_LEAD_IMPORT.FIELD_TYPES.INTEGER') },
  { value: 'float', label: t('JABVOX_LEAD_IMPORT.FIELD_TYPES.FLOAT') },
  { value: 'boolean', label: t('JABVOX_LEAD_IMPORT.FIELD_TYPES.BOOLEAN') },
  { value: 'date', label: t('JABVOX_LEAD_IMPORT.FIELD_TYPES.DATE') },
  { value: 'select', label: t('JABVOX_LEAD_IMPORT.FIELD_TYPES.SELECT') },
]);

// ---------- List / CRUD ----------
const loadSources = async () => {
  const { data } = await leadSourcesAPI.getAll();
  sources.value = data.sources || [];
};

const newSource = () => ({
  name_jabvox: '',
  engine_jabvox: 'mysql',
  host_jabvox: '',
  port_jabvox: null,
  database_jabvox: '',
  username_jabvox: '',
  password_jabvox: '',
  ssl_mode_jabvox: 'prefer',
  allow_private_network_jabvox: false,
});

const openNew = () => {
  editing.value = newSource();
  testResult.value = null;
};
const openEdit = source => {
  editing.value = { ...source, password_jabvox: '' };
  testResult.value = null;
};
const cancelEdit = () => {
  editing.value = null;
  testResult.value = null;
};

const testConnection = async () => {
  testing.value = true;
  testResult.value = null;
  try {
    const { data } = await leadSourcesAPI.test(editing.value);
    testResult.value = data;
  } catch (e) {
    testResult.value = {
      success: false,
      message: apiError(e, 'JABVOX_LEAD_IMPORT.TEST_ERROR'),
    };
  } finally {
    testing.value = false;
  }
};

const saveSource = async () => {
  try {
    if (editing.value.id) {
      await leadSourcesAPI.update(editing.value.id, editing.value);
    } else {
      await leadSourcesAPI.create(editing.value);
    }
    editing.value = null;
    await loadSources();
    useAlert(t('JABVOX_LEAD_IMPORT.SAVED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_LEAD_IMPORT.SAVE_ERROR'));
  }
};

// Delete dialog with two choices: keep imported leads, or move them to the
// (restorable) trash. The backend receives purge_leads accordingly.
const deletingSource = ref(null);
const deletingBusy = ref(false);
const askDelete = source => {
  deletingSource.value = source;
};
const confirmDelete = async purgeLeads => {
  deletingBusy.value = true;
  try {
    await leadSourcesAPI.destroy(deletingSource.value.id, purgeLeads);
    deletingSource.value = null;
    await loadSources();
    useAlert(t('JABVOX_LEAD_IMPORT.DELETED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_LEAD_IMPORT.SAVE_ERROR'));
  } finally {
    deletingBusy.value = false;
  }
};

// Test connection of an already-saved source (manual, from the list).
const testingId = ref(null);
const testSaved = async source => {
  testingId.value = source.id;
  try {
    const { data } = await leadSourcesAPI.testSaved(source.id);
    useAlert(
      data.success
        ? t('JABVOX_LEAD_IMPORT.TEST_OK')
        : data.message || t('JABVOX_LEAD_IMPORT.TEST_ERROR')
    );
    await loadSources();
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_LEAD_IMPORT.TEST_ERROR'));
  } finally {
    testingId.value = null;
  }
};

// ---------- Mapping ----------
const openMapping = async source => {
  loadingSchema.value = true;
  try {
    const [tablesRes, fieldsRes] = await Promise.all([
      leadSourcesAPI.tables(source.id),
      leadSourcesAPI.leadFields(),
    ]);
    const leadFields = [
      ...(fieldsRes.data.standard || []),
      ...(fieldsRes.data.custom || []),
    ];
    mapping.value = {
      source,
      tables: tablesRes.data.tables || [],
      leadFields,
      table: source.table_jabvox || '',
      externalIdColumn: source.external_id_column_jabvox || '',
      map: { ...(source.field_mapping_jabvox || {}) },
      related: (source.related_tables_jabvox || []).map(r => ({ ...r })),
      phonePrefix: source.phone_prefix_jabvox || '',
      filters: (source.filters_jabvox || []).map(f => ({
        column: f.column || '',
        op: f.op || 'eq',
        value: f.value ?? '',
        value2: f.value2 ?? '',
      })),
    };
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_LEAD_IMPORT.SCHEMA_ERROR'));
  } finally {
    loadingSchema.value = false;
  }
};

const columnsOf = tableName => {
  const tbl = mapping.value?.tables.find(x => x.name === tableName);
  return tbl?.columns || [];
};

// Columns available to map: the main table's own columns plus each related
// table's columns exposed as "alias.column" (matching how the sync returns them).
const currentTableColumns = computed(() => {
  if (!mapping.value?.table) return [];
  const own = columnsOf(mapping.value.table).map(c => ({
    name: c.name,
    type: c.type,
  }));
  const related = (mapping.value.related || []).flatMap(rel => {
    const als = (rel.alias || rel.table || '').replace(/[^a-zA-Z0-9_]/g, '');
    if (!rel.table || !als) return [];
    return columnsOf(rel.table).map(c => ({
      name: `${als}.${c.name}`,
      type: c.type,
    }));
  });
  return [...own, ...related];
});

// Search box to filter the external columns (left side of the mapping table).
const columnSearch = ref('');
const filteredTableColumns = computed(() => {
  const term = columnSearch.value.trim().toLowerCase();
  if (!term) return currentTableColumns.value;
  return currentTableColumns.value.filter(c =>
    c.name.toLowerCase().includes(term)
  );
});

const tableOptions = computed(() =>
  (mapping.value?.tables || []).map(x => ({ value: x.name, label: x.name }))
);
const idColumnOptions = computed(() =>
  currentTableColumns.value.map(c => ({ value: c.name, label: c.name }))
);
// Sentinel value for the "Create field…" entry inside the dropdown.
const CREATE_FIELD_OPTION = '__create__';

// The Select is keyed by the field's unique `key`; the real `kind` (which may
// itself contain ':', e.g. "attr:city") is looked up from leadFields — so no
// fragile string splitting. The last option lets the user create a field on the spot.
const leadFieldOptions = computed(() => [
  { value: '', label: t('JABVOX_LEAD_IMPORT.MAP.IGNORE') },
  ...(mapping.value?.leadFields || []).map(f => ({
    value: f.key,
    label: f.label,
  })),
  {
    value: CREATE_FIELD_OPTION,
    label: t('JABVOX_LEAD_IMPORT.MAP.CREATE_OPTION'),
  },
]);

// map holds { externalColumn: { target, kind } }; the Select's value is target (key).
const mapValueFor = col => mapping.value.map[col]?.target || '';

// Human label + destination type for a mapped target key (for the summary table).
const leadFieldByKey = key =>
  (mapping.value?.leadFields || []).find(f => f.key === key);
const destLabelFor = key => leadFieldByKey(key)?.label || key;
const destTypeFor = key => {
  const f = leadFieldByKey(key);
  if (!f) return '';
  // Custom fields carry their own column_type; standard ones map to a friendly type.
  const type = f.kind === 'custom' ? f.column_type || 'text' : 'text';
  return t(`JABVOX_LEAD_IMPORT.FIELD_TYPES.${type.toUpperCase()}`);
};
const externalTypeFor = colName => {
  const col = currentTableColumns.value.find(c => c.name === colName);
  return col?.type || '';
};

// Every column that already has a destination field, for the summary table.
const mappedEntries = computed(() =>
  Object.entries(mapping.value?.map || {})
    .filter(([, v]) => v && v.target)
    .map(([col, v]) => ({
      column: col,
      externalType: externalTypeFor(col),
      target: v.target,
      destLabel: destLabelFor(v.target),
      destType: destTypeFor(v.target),
    }))
);
const unmappedCount = computed(
  () => currentTableColumns.value.length - mappedEntries.value.length
);
const clearMapping = col => {
  delete mapping.value.map[col];
};

// Create a new custom field on the fly and select it for this column. Prefills
// the label with the external column name for convenience.
const creatingFieldFor = ref(null);
const newField = ref({ name: '', label: '', column_type: 'text' });
// Infers a sensible field type from the external column's DB type so the user
// doesn't have to pick it manually (and imports don't fail on bad casts).
const inferFieldType = colName => {
  const raw = (externalTypeFor(colName) || '').toLowerCase();
  if (/int|serial|bigint|smallint/.test(raw)) return 'integer';
  if (/decimal|numeric|float|double|real|money/.test(raw)) return 'float';
  if (/bool|bit|tinyint\(1\)/.test(raw)) return 'boolean';
  if (/date|time/.test(raw)) return 'date';
  return 'text';
};
const startCreateField = col => {
  creatingFieldFor.value = col;
  const base = String(col).split('.').pop();
  newField.value = {
    name: base,
    label: base,
    column_type: inferFieldType(col),
  };
};

// Selecting a lead field for a column. Choosing "Create field…" opens the modal
// for that specific column instead of assigning an existing field.
// Assigns an existing lead field (by key) to a column, or clears it if empty.
const assignField = (col, value) => {
  if (!value) {
    delete mapping.value.map[col];
    return;
  }
  const field = (mapping.value.leadFields || []).find(f => f.key === value);
  if (!field) return;
  mapping.value.map[col] = { target: field.key, kind: field.kind };
};

const setMapValue = (col, value) => {
  if (value === CREATE_FIELD_OPTION) {
    startCreateField(col);
    return;
  }
  assignField(col, value);
};
const creatingSaving = ref(false);
const submitCreateField = async () => {
  if (!newField.value.label.trim()) {
    useAlert(t('JABVOX_LEAD_IMPORT.CREATE_FIELD.LABEL_REQUIRED'));
    return;
  }
  const col = creatingFieldFor.value;
  creatingSaving.value = true;
  try {
    const { data } = await leadSourcesAPI.createCustomField({
      name: newField.value.name || newField.value.label,
      label: newField.value.label,
      column_type: newField.value.column_type,
    });
    // If the field already existed (same key), reuse it instead of duplicating.
    if (!mapping.value.leadFields.some(f => f.key === data.key)) {
      mapping.value.leadFields.push({
        key: data.key,
        label: data.label,
        kind: 'custom',
        column_type: data.column_type,
      });
    }
    assignField(col, data.key); // select the created (or existing) field
    creatingFieldFor.value = null;
    useAlert(t('JABVOX_LEAD_IMPORT.FIELD_CREATED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_LEAD_IMPORT.FIELD_ERROR'));
  } finally {
    creatingSaving.value = false;
  }
};

// Cancelling the create dialog leaves the column as "Do not import".
const cancelCreateField = () => {
  if (creatingFieldFor.value) delete mapping.value.map[creatingFieldFor.value];
  creatingFieldFor.value = null;
};

// ---------- Related tables (JOINs) ----------
const allTableOptions = computed(() =>
  (mapping.value?.tables || []).map(x => ({ value: x.name, label: x.name }))
);
// Options for the "Main table key" of a related table at position `index`.
// It can reference a column of the main table (e.g. "id") OR a column of any
// related table defined BEFORE it (e.g. "cstm.mg_c") — this enables chained
// joins like leads → leads_cstm → lk_mail_plan.
const mainTableKeyOptions = index => {
  const opts = columnsOf(mapping.value?.table).map(c => ({
    value: c.name,
    label: c.name,
  }));
  (mapping.value?.related || []).slice(0, index).forEach(rel => {
    const als = (rel.alias || rel.table || '').replace(/[^a-zA-Z0-9_]/g, '');
    if (!rel.table || !als) return;
    columnsOf(rel.table).forEach(c => {
      opts.push({ value: `${als}.${c.name}`, label: `${als}.${c.name}` });
    });
  });
  return opts;
};
const relatedColumnOptions = rel => {
  if (!rel.table) return [];
  return columnsOf(rel.table).map(c => ({ value: c.name, label: c.name }));
};
const addRelated = () => {
  mapping.value.related.push({
    table: '',
    local_key: '',
    foreign_key: '',
    alias: '',
  });
};
const removeRelated = index => {
  mapping.value.related.splice(index, 1);
};

// ---------- Sync filters ----------
// Operators that filter by presence only — no value input is shown or sent.
const OPS_WITHOUT_VALUE = ['null', 'not_null'];
const filterOpOptions = computed(() =>
  [
    'eq',
    'neq',
    'gt',
    'gte',
    'lt',
    'lte',
    'between',
    'contains',
    'null',
    'not_null',
  ].map(op => ({
    value: op,
    label: t(`JABVOX_LEAD_IMPORT.FILTERS.OPS.${op.toUpperCase()}`),
  }))
);
const filterNeedsValue = op => !OPS_WITHOUT_VALUE.includes(op);
const addFilter = () => {
  mapping.value.filters.push({ column: '', op: 'eq', value: '', value2: '' });
};
const removeFilter = index => {
  mapping.value.filters.splice(index, 1);
};

const saveMapping = async () => {
  const m = mapping.value;
  if (!m.table || !m.externalIdColumn) {
    useAlert(t('JABVOX_LEAD_IMPORT.MAP.REQUIRED'));
    return;
  }
  // Keep only complete related-table rows.
  const related = (m.related || []).filter(
    r => r.table && r.local_key && r.foreign_key
  );
  // Keep only complete filter rows; `between` needs both bounds, and the
  // presence operators (null / not_null) are sent without values.
  const filterRows = (m.filters || []).filter(f => f.column && f.op);
  if (
    filterRows.some(
      f => f.op === 'between' && (f.value === '' || f.value2 === '')
    )
  ) {
    useAlert(t('JABVOX_LEAD_IMPORT.FILTERS.BETWEEN_REQUIRED'));
    return;
  }
  const filters = filterRows.map(f => ({
    column: f.column,
    op: f.op,
    value: filterNeedsValue(f.op) ? f.value : '',
    value2: f.op === 'between' ? f.value2 : '',
  }));
  try {
    await leadSourcesAPI.update(m.source.id, {
      table_jabvox: m.table,
      external_id_column_jabvox: m.externalIdColumn,
      field_mapping_jabvox: m.map,
      related_tables_jabvox: related,
      phone_prefix_jabvox: m.phonePrefix,
      filters_jabvox: filters,
    });
    mapping.value = null;
    await loadSources();
    useAlert(t('JABVOX_LEAD_IMPORT.SAVED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_LEAD_IMPORT.SAVE_ERROR'));
  }
};

// ---------- Sync ----------
const pollSync = id => {
  clearInterval(pollTimer);
  pollTimer = setInterval(async () => {
    const { data } = await leadSourcesAPI.syncStatus(id);
    const idx = sources.value.findIndex(s => s.id === id);
    if (idx !== -1) {
      sources.value[idx] = {
        ...sources.value[idx],
        status_jabvox: data.status,
        last_synced_at_jabvox: data.last_synced_at,
        last_sync_result_jabvox: data.last_result,
      };
    }
    if (data.status !== 'syncing') {
      clearInterval(pollTimer);
      syncingId.value = null;
    }
  }, 2500);
};

// A source can only sync once it has a table, an id column and at least one
// mapped field. Guard here (the backend also enforces it) and confirm first.
const isMapped = source =>
  !!source.table_jabvox &&
  !!source.external_id_column_jabvox &&
  source.field_mapping_jabvox &&
  Object.keys(source.field_mapping_jabvox).length > 0;

const syncSource = source => {
  if (!isMapped(source)) {
    useAlert(t('JABVOX_LEAD_IMPORT.SYNC_NEEDS_MAPPING'));
    return;
  }
  confirmDialog.value?.open({
    title: t('JABVOX_LEAD_IMPORT.SYNC'),
    description: t('JABVOX_LEAD_IMPORT.SYNC_CONFIRM'),
    confirmLabel: t('JABVOX_LEAD_IMPORT.SYNC'),
    cancelLabel: t('JABVOX_LEAD_IMPORT.FORM.CANCEL'),
    data: source.id,
  });
};

const doSync = async sourceId => {
  try {
    await leadSourcesAPI.sync(sourceId);
    syncingId.value = sourceId;
    pollSync(sourceId);
    useAlert(t('JABVOX_LEAD_IMPORT.SYNC_STARTED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_LEAD_IMPORT.SYNC_ERROR'));
  }
};

onMounted(loadSources);
onUnmounted(() => clearInterval(pollTimer));
</script>

<template>
  <div class="flex flex-col flex-1 overflow-auto bg-n-background">
    <div class="w-full max-w-[1100px] mx-auto px-6 py-8">
      <header class="mb-6">
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ t('JABVOX_LEAD_IMPORT.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('JABVOX_LEAD_IMPORT.SUBTITLE') }}
        </p>
      </header>

      <!-- ============ CONNECTION FORM ============ -->
      <section
        v-if="editing"
        class="rounded-2xl bg-n-solid-1 border border-n-weak p-6 flex flex-col gap-4"
      >
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{
            editing.id
              ? t('JABVOX_LEAD_IMPORT.FORM.EDIT_TITLE')
              : t('JABVOX_LEAD_IMPORT.FORM.NEW_TITLE')
          }}
        </h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="editing.name_jabvox"
            :label="t('JABVOX_LEAD_IMPORT.FORM.NAME')"
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_LEAD_IMPORT.FORM.ENGINE') }}
            </label>
            <Select v-model="editing.engine_jabvox" :options="engineOptions" />
          </div>
          <Input
            v-model="editing.host_jabvox"
            :label="t('JABVOX_LEAD_IMPORT.FORM.HOST')"
          />
          <Input
            v-model="editing.port_jabvox"
            type="number"
            :label="t('JABVOX_LEAD_IMPORT.FORM.PORT')"
          />
          <Input
            v-model="editing.database_jabvox"
            :label="t('JABVOX_LEAD_IMPORT.FORM.DATABASE')"
          />
          <Input
            v-model="editing.username_jabvox"
            :label="t('JABVOX_LEAD_IMPORT.FORM.USERNAME')"
          />
          <Input
            v-model="editing.password_jabvox"
            type="password"
            :label="t('JABVOX_LEAD_IMPORT.FORM.PASSWORD')"
            :placeholder="
              editing.has_password
                ? t('JABVOX_LEAD_IMPORT.FORM.PASSWORD_KEEP')
                : ''
            "
          />
        </div>

        <div
          v-if="testResult"
          class="text-sm rounded-lg px-3 py-2"
          :class="
            testResult.success
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{ testResult.message }}
        </div>

        <div class="flex items-center gap-2">
          <Button
            :label="t('JABVOX_LEAD_IMPORT.FORM.TEST')"
            variant="outline"
            color="slate"
            :is-loading="testing"
            @click="testConnection"
          />
          <Button
            class="ml-auto"
            :label="t('JABVOX_LEAD_IMPORT.FORM.SAVE')"
            @click="saveSource"
          />
          <Button
            :label="t('JABVOX_LEAD_IMPORT.FORM.CANCEL')"
            variant="ghost"
            color="slate"
            @click="cancelEdit"
          />
        </div>
      </section>

      <!-- ============ MAPPING ============ -->
      <section
        v-else-if="mapping"
        class="rounded-2xl bg-n-solid-1 border border-n-weak p-6 flex flex-col gap-4"
      >
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{
            t('JABVOX_LEAD_IMPORT.MAP.TITLE', {
              name: mapping.source.name_jabvox,
            })
          }}
        </h2>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_LEAD_IMPORT.MAP.TABLE') }}
            </label>
            <ComboBox
              v-model="mapping.table"
              :options="tableOptions"
              :search-placeholder="t('JABVOX_LEAD_IMPORT.MAP.SEARCH_TABLE')"
              :empty-state="t('JABVOX_LEAD_IMPORT.MAP.NO_RESULTS')"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_LEAD_IMPORT.MAP.ID_COLUMN') }}
            </label>
            <ComboBox
              v-model="mapping.externalIdColumn"
              :options="idColumnOptions"
              :search-placeholder="t('JABVOX_LEAD_IMPORT.MAP.SEARCH_COLUMN')"
              :empty-state="t('JABVOX_LEAD_IMPORT.MAP.NO_RESULTS')"
            />
          </div>
        </div>

        <!-- Related tables (JOINs) -->
        <div v-if="mapping.table" class="flex flex-col gap-3">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_LEAD_IMPORT.RELATED.TITLE') }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_LEAD_IMPORT.RELATED.HINT') }}
              </p>
            </div>
            <Button
              :label="t('JABVOX_LEAD_IMPORT.RELATED.ADD')"
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-plus"
              @click="addRelated"
            />
          </div>

          <div
            v-for="(rel, i) in mapping.related"
            :key="i"
            class="grid grid-cols-1 sm:grid-cols-[1fr_1fr_1fr_1fr_auto] gap-2 items-end rounded-xl border border-n-weak p-3"
          >
            <div class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_LEAD_IMPORT.RELATED.TABLE') }}
              </span>
              <ComboBox
                v-model="rel.table"
                :options="allTableOptions"
                :search-placeholder="t('JABVOX_LEAD_IMPORT.MAP.SEARCH_TABLE')"
                :empty-state="t('JABVOX_LEAD_IMPORT.MAP.NO_RESULTS')"
              />
            </div>
            <div class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_LEAD_IMPORT.RELATED.LOCAL_KEY') }}
              </span>
              <ComboBox
                v-model="rel.local_key"
                :options="mainTableKeyOptions(i)"
                :search-placeholder="t('JABVOX_LEAD_IMPORT.MAP.SEARCH_COLUMN')"
                :empty-state="t('JABVOX_LEAD_IMPORT.MAP.NO_RESULTS')"
              />
            </div>
            <div class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_LEAD_IMPORT.RELATED.FOREIGN_KEY') }}
              </span>
              <ComboBox
                v-model="rel.foreign_key"
                :options="relatedColumnOptions(rel)"
                :search-placeholder="t('JABVOX_LEAD_IMPORT.MAP.SEARCH_COLUMN')"
                :empty-state="t('JABVOX_LEAD_IMPORT.MAP.NO_RESULTS')"
              />
            </div>
            <Input
              v-model="rel.alias"
              :label="t('JABVOX_LEAD_IMPORT.RELATED.ALIAS')"
            />
            <Button
              variant="ghost"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              @click="removeRelated(i)"
            />
          </div>
        </div>

        <!-- Phone prefix (E.164 normalization) -->
        <div v-if="mapping.table" class="flex flex-col gap-1.5">
          <Input
            v-model="mapping.phonePrefix"
            class="max-w-[12rem]"
            :label="t('JABVOX_LEAD_IMPORT.PHONE_PREFIX.LABEL')"
            placeholder="57"
          />
          <p class="text-xs text-n-slate-11">
            {{ t('JABVOX_LEAD_IMPORT.PHONE_PREFIX.HINT') }}
          </p>
        </div>

        <!-- Sync filters (rows must match ALL of them) -->
        <div v-if="mapping.table" class="flex flex-col gap-3">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_LEAD_IMPORT.FILTERS.TITLE') }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_LEAD_IMPORT.FILTERS.HINT') }}
              </p>
            </div>
            <Button
              :label="t('JABVOX_LEAD_IMPORT.FILTERS.ADD')"
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-plus"
              @click="addFilter"
            />
          </div>

          <div
            v-for="(f, i) in mapping.filters"
            :key="i"
            class="grid grid-cols-1 sm:grid-cols-[1.4fr_1fr_1fr_1fr_auto] gap-2 items-end rounded-xl border border-n-weak p-3"
          >
            <div class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_LEAD_IMPORT.FILTERS.COLUMN') }}
              </span>
              <ComboBox
                v-model="f.column"
                :options="idColumnOptions"
                :search-placeholder="t('JABVOX_LEAD_IMPORT.MAP.SEARCH_COLUMN')"
                :empty-state="t('JABVOX_LEAD_IMPORT.MAP.NO_RESULTS')"
              />
            </div>
            <div class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_LEAD_IMPORT.FILTERS.OPERATOR') }}
              </span>
              <Select v-model="f.op" :options="filterOpOptions" />
            </div>
            <Input
              v-if="filterNeedsValue(f.op)"
              v-model="f.value"
              :label="t('JABVOX_LEAD_IMPORT.FILTERS.VALUE')"
            />
            <div v-else />
            <Input
              v-if="f.op === 'between'"
              v-model="f.value2"
              :label="t('JABVOX_LEAD_IMPORT.FILTERS.VALUE2')"
            />
            <div v-else />
            <Button
              variant="ghost"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              @click="removeFilter(i)"
            />
          </div>
        </div>

        <!-- Column → field mapping -->
        <div v-if="mapping.table" class="flex flex-col gap-2">
          <Input
            v-model="columnSearch"
            :placeholder="t('JABVOX_LEAD_IMPORT.MAP.SEARCH_COLUMN')"
            class="max-w-xs"
          />
          <div class="rounded-xl border border-n-weak divide-y divide-n-weak">
            <div
              class="grid grid-cols-[1fr_1fr] gap-3 px-3 py-2 bg-n-alpha-1 text-[11px] font-semibold uppercase text-n-slate-10"
            >
              <span>{{ t('JABVOX_LEAD_IMPORT.MAP.EXTERNAL_COLUMN') }}</span>
              <span>{{ t('JABVOX_LEAD_IMPORT.MAP.LEAD_FIELD') }}</span>
            </div>
            <div
              v-for="col in filteredTableColumns"
              :key="col.name"
              class="grid grid-cols-[1fr_1fr] gap-3 items-center px-3 py-2 text-sm"
            >
              <span class="text-n-slate-12 truncate">
                {{ col.name }}
                <span class="text-n-slate-10 text-xs">({{ col.type }})</span>
              </span>
              <ComboBox
                :model-value="mapValueFor(col.name)"
                :options="leadFieldOptions"
                :placeholder="t('JABVOX_LEAD_IMPORT.MAP.LEAD_FIELD')"
                @update:model-value="setMapValue(col.name, $event)"
              />
            </div>
            <div
              v-if="!filteredTableColumns.length"
              class="px-3 py-4 text-sm text-n-slate-10 text-center"
            >
              {{ t('JABVOX_LEAD_IMPORT.MAP.NO_COLUMNS') }}
            </div>
          </div>
        </div>

        <!-- Summary of what has been mapped so far -->
        <div v-if="mapping.table" class="flex flex-col gap-2">
          <div class="flex items-center gap-2">
            <h4 class="text-sm font-semibold text-n-slate-12">
              {{ t('JABVOX_LEAD_IMPORT.SUMMARY.TITLE') }}
            </h4>
            <span
              class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium bg-n-teal-3 text-n-teal-11"
            >
              {{
                t('JABVOX_LEAD_IMPORT.SUMMARY.MAPPED', {
                  count: mappedEntries.length,
                })
              }}
            </span>
            <span
              v-if="unmappedCount > 0"
              class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium bg-n-amber-3 text-n-amber-11"
            >
              {{
                t('JABVOX_LEAD_IMPORT.SUMMARY.UNMAPPED', {
                  count: unmappedCount,
                })
              }}
            </span>
          </div>
          <div
            v-if="mappedEntries.length"
            class="rounded-xl border border-n-weak overflow-hidden"
          >
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="bg-n-alpha-1 text-[11px] font-semibold uppercase text-n-slate-10 text-left"
                >
                  <th class="px-3 py-2">
                    {{ t('JABVOX_LEAD_IMPORT.SUMMARY.SOURCE_COLUMN') }}
                  </th>
                  <th class="px-3 py-2">
                    {{ t('JABVOX_LEAD_IMPORT.SUMMARY.SOURCE_TYPE') }}
                  </th>
                  <th class="px-3 py-2">
                    {{ t('JABVOX_LEAD_IMPORT.SUMMARY.DEST_FIELD') }}
                  </th>
                  <th class="px-3 py-2">
                    {{ t('JABVOX_LEAD_IMPORT.SUMMARY.DEST_TYPE') }}
                  </th>
                  <th class="px-3 py-2 w-10" />
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr v-for="row in mappedEntries" :key="row.column">
                  <td class="px-3 py-2 font-mono text-n-slate-12">
                    {{ row.column }}
                  </td>
                  <td class="px-3 py-2 text-n-slate-10 text-xs">
                    {{ row.externalType || '—' }}
                  </td>
                  <td class="px-3 py-2 text-n-slate-12">
                    <span
                      class="inline-flex items-center gap-1 before:content-['→'] before:text-n-slate-9"
                    >
                      {{ row.destLabel }}
                    </span>
                  </td>
                  <td class="px-3 py-2">
                    <span
                      class="inline-flex items-center px-1.5 py-0.5 rounded-md text-[11px] font-medium bg-n-alpha-1 text-n-slate-11"
                    >
                      {{ row.destType }}
                    </span>
                  </td>
                  <td class="px-3 py-2 text-right">
                    <Button
                      variant="ghost"
                      color="ruby"
                      size="sm"
                      icon="i-lucide-x"
                      @click="clearMapping(row.column)"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p v-else class="text-sm text-n-slate-10">
            {{ t('JABVOX_LEAD_IMPORT.SUMMARY.EMPTY') }}
          </p>
        </div>

        <div class="flex items-center gap-2">
          <Button
            class="ml-auto"
            :label="t('JABVOX_LEAD_IMPORT.MAP.SAVE')"
            @click="saveMapping"
          />
          <Button
            :label="t('JABVOX_LEAD_IMPORT.FORM.CANCEL')"
            variant="ghost"
            color="slate"
            @click="mapping = null"
          />
        </div>
      </section>

      <!-- ============ LIST ============ -->
      <section v-else class="flex flex-col gap-4">
        <div class="flex justify-end">
          <Button
            :label="t('JABVOX_LEAD_IMPORT.NEW')"
            icon="i-lucide-plus"
            @click="openNew"
          />
        </div>

        <p
          v-if="!sources.length"
          class="text-sm text-n-slate-11 text-center py-10 rounded-2xl border border-dashed border-n-weak"
        >
          {{ t('JABVOX_LEAD_IMPORT.EMPTY') }}
        </p>

        <div
          v-for="source in sources"
          :key="source.id"
          class="rounded-2xl bg-n-solid-1 border border-n-weak p-4 flex items-center gap-4"
        >
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-n-slate-12 truncate">
              {{ source.name_jabvox }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ source.engine_jabvox }} · {{ source.host_jabvox }}
              <span v-if="source.table_jabvox">
                · {{ source.table_jabvox }}
              </span>
            </p>
            <p
              v-if="
                source.last_sync_result_jabvox &&
                source.last_sync_result_jabvox.at
              "
              class="text-xs text-n-slate-10 mt-0.5"
            >
              {{
                t('JABVOX_LEAD_IMPORT.LAST_SYNC', {
                  created: source.last_sync_result_jabvox.created || 0,
                  updated: source.last_sync_result_jabvox.updated || 0,
                  failed: source.last_sync_result_jabvox.failed || 0,
                })
              }}
            </p>
          </div>
          <span
            v-if="source.status_jabvox === 'syncing'"
            class="flex items-center gap-1.5 text-xs text-n-amber-11"
          >
            <Spinner :size="14" />
            {{ t('JABVOX_LEAD_IMPORT.SYNCING') }}
          </span>
          <div class="flex items-center gap-1.5 shrink-0">
            <Button
              :label="t('JABVOX_LEAD_IMPORT.FORM.TEST')"
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-plug-zap"
              :is-loading="testingId === source.id"
              @click="testSaved(source)"
            />
            <Button
              :label="t('JABVOX_LEAD_IMPORT.MAP.BUTTON')"
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-arrow-left-right"
              @click="openMapping(source)"
            />
            <Button
              :label="t('JABVOX_LEAD_IMPORT.SYNC')"
              size="sm"
              icon="i-lucide-refresh-cw"
              :disabled="
                source.status_jabvox === 'syncing' || !isMapped(source)
              "
              :title="
                isMapped(source)
                  ? ''
                  : t('JABVOX_LEAD_IMPORT.SYNC_NEEDS_MAPPING')
              "
              @click="syncSource(source)"
            />
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              icon="i-lucide-pencil"
              @click="openEdit(source)"
            />
            <Button
              variant="ghost"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              @click="askDelete(source)"
            />
          </div>
        </div>
      </section>

      <p v-if="loadingSchema" class="text-sm text-n-slate-11 mt-4">
        {{ t('JABVOX_LEAD_IMPORT.LOADING_SCHEMA') }}
      </p>
    </div>

    <!-- Create custom field modal -->
    <div
      v-if="creatingFieldFor"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-4"
      @click.self="cancelCreateField"
    >
      <div
        class="w-full max-w-sm rounded-2xl bg-n-solid-1 border border-n-weak p-6 flex flex-col gap-4"
      >
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ t('JABVOX_LEAD_IMPORT.CREATE_FIELD.TITLE') }}
        </h3>
        <p class="text-xs text-n-slate-11 -mt-2">
          {{
            t('JABVOX_LEAD_IMPORT.CREATE_FIELD.FOR_COLUMN', {
              column: creatingFieldFor,
            })
          }}
        </p>
        <Input
          v-model="newField.label"
          :label="t('JABVOX_LEAD_IMPORT.CREATE_FIELD.LABEL')"
        />
        <Input
          v-model="newField.name"
          :label="t('JABVOX_LEAD_IMPORT.CREATE_FIELD.KEY')"
          :placeholder="t('JABVOX_LEAD_IMPORT.CREATE_FIELD.KEY_HINT')"
        />
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_LEAD_IMPORT.CREATE_FIELD.TYPE') }}
          </label>
          <Select v-model="newField.column_type" :options="fieldTypeOptions" />
        </div>
        <div class="flex justify-end gap-2">
          <Button
            :label="t('JABVOX_LEAD_IMPORT.FORM.CANCEL')"
            variant="ghost"
            color="slate"
            :disabled="creatingSaving"
            @click="cancelCreateField"
          />
          <Button
            :label="t('JABVOX_LEAD_IMPORT.CREATE_FIELD.CREATE')"
            :is-loading="creatingSaving"
            @click="submitCreateField"
          />
        </div>
      </div>
    </div>

    <!-- Delete connection dialog (keep leads vs move to trash) -->
    <div
      v-if="deletingSource"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-4"
      @click.self="deletingSource = null"
    >
      <div
        class="w-full max-w-md rounded-2xl bg-n-solid-1 border border-n-weak p-6 flex flex-col gap-4"
      >
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ t('JABVOX_LEAD_IMPORT.DELETE.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_LEAD_IMPORT.DELETE.BODY') }}
        </p>
        <div class="flex flex-col gap-2">
          <Button
            :label="t('JABVOX_LEAD_IMPORT.DELETE.KEEP')"
            variant="outline"
            color="slate"
            :disabled="deletingBusy"
            @click="confirmDelete(false)"
          />
          <Button
            :label="t('JABVOX_LEAD_IMPORT.DELETE.PURGE')"
            color="ruby"
            :is-loading="deletingBusy"
            @click="confirmDelete(true)"
          />
          <Button
            :label="t('JABVOX_LEAD_IMPORT.FORM.CANCEL')"
            variant="ghost"
            color="slate"
            :disabled="deletingBusy"
            @click="deletingSource = null"
          />
        </div>
        <p class="text-xs text-n-slate-10">
          {{ t('JABVOX_LEAD_IMPORT.DELETE.TRASH_HINT') }}
        </p>
      </div>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="doSync" />
  </div>
</template>
