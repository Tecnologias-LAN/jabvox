<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dataExportAPI } from 'dashboard/api/jabvox/dataExport';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const apiError = (e, fallback) => e?.response?.data?.error || t(fallback);

const target = ref(null); // the saved target, or null
const editing = ref(null); // the form model when creating/editing
const testResult = ref(null);
const testing = ref(false);
const building = ref(false);
const confirmDialog = ref(null);

// ---------- Field mapping (map mode) ----------
const remoteTables = ref([]); // [{ name, columns: [{ name, type }] }]
const jabvoxTables = ref([]); // [{ table, columns: [..strings..] }]
const detecting = ref(false);
const schemaLoaded = ref(false);
const createMissing = ref(false);
// map holds { jabvoxTable: { key: '<customerCol>', columns: { jabvoxCol: customerCol } } }
const map = ref({});
const savingMapping = ref(false);
const syncing = ref(false);

const engineOptions = computed(() => [
  { value: 'postgresql', label: 'PostgreSQL' },
  { value: 'mysql', label: 'MySQL' },
  { value: 'mariadb', label: 'MariaDB' },
]);

const modeOptions = computed(() => [
  { value: 'create', label: t('JABVOX_DATA_EXPORT.MODE.CREATE') },
  { value: 'map', label: t('JABVOX_DATA_EXPORT.MODE.MAP') },
]);

const load = async () => {
  const { data } = await dataExportAPI.getAll();
  target.value = (data.targets || [])[0] || null;
};

const newTarget = () => ({
  name_jabvox: '',
  engine_jabvox: 'postgresql',
  host_jabvox: '',
  port_jabvox: null,
  database_jabvox: '',
  username_jabvox: '',
  password_jabvox: '',
  ssl_mode_jabvox: 'prefer',
  allow_private_network_jabvox: false,
  mode_jabvox: 'create',
});

const openNew = () => {
  editing.value = newTarget();
  testResult.value = null;
};
const openEdit = () => {
  editing.value = { ...target.value, password_jabvox: '' };
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
    const { data } = await dataExportAPI.test(editing.value);
    testResult.value = data;
  } catch (e) {
    testResult.value = {
      success: false,
      message: apiError(e, 'JABVOX_DATA_EXPORT.TEST_ERROR'),
    };
  } finally {
    testing.value = false;
  }
};

const save = async () => {
  try {
    if (editing.value.id) {
      await dataExportAPI.update(editing.value.id, editing.value);
    } else {
      await dataExportAPI.create(editing.value);
    }
    editing.value = null;
    await load();
    useAlert(t('JABVOX_DATA_EXPORT.SAVED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SAVE_ERROR'));
  }
};

const remove = () => {
  confirmDialog.value?.open({
    title: t('JABVOX_DATA_EXPORT.DELETE'),
    description: t('JABVOX_DATA_EXPORT.DELETE_CONFIRM'),
    confirmLabel: t('JABVOX_DATA_EXPORT.DELETE'),
    cancelLabel: t('JABVOX_DATA_EXPORT.FORM.CANCEL'),
    data: target.value.id,
  });
};

const doRemove = async id => {
  await dataExportAPI.destroy(id);
  await load();
};

const testSaved = async () => {
  testing.value = true;
  try {
    const { data } = await dataExportAPI.testSaved(target.value.id);
    useAlert(data.success ? t('JABVOX_DATA_EXPORT.TEST_OK') : data.message);
    await load();
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.TEST_ERROR'));
  } finally {
    testing.value = false;
  }
};

const buildSchema = async () => {
  building.value = true;
  try {
    await dataExportAPI.buildSchema(target.value.id);
    await load();
    useAlert(t('JABVOX_DATA_EXPORT.SCHEMA_BUILT'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SCHEMA_ERROR'));
  } finally {
    building.value = false;
  }
};

const toggleEnabled = async value => {
  try {
    const { data } = await dataExportAPI.toggle(target.value.id, value);
    target.value = data;
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SAVE_ERROR'));
  }
};

// ---------- Field mapping (map mode) ----------
// The remote (customer) table that matches a jabvox table name, if any.
const remoteTableFor = jabvoxTableName =>
  remoteTables.value.find(rt => rt.name === jabvoxTableName) || null;

// Customer column options for a given jabvox table (empty option = unmapped).
const customerColumnOptions = jabvoxTableName => {
  const rt = remoteTableFor(jabvoxTableName);
  const cols = (rt?.columns || []).map(c => ({
    value: c.name,
    label: c.type ? `${c.name} (${c.type})` : c.name,
  }));
  return [{ value: '', label: t('JABVOX_DATA_EXPORT.MAP.UNMAPPED') }, ...cols];
};

// The customer columns the user has already mapped in this table — the only
// valid candidates for the "key" column.
const mappedCustomerColumns = jabvoxTableName => {
  const cols = map.value[jabvoxTableName]?.columns || {};
  return Object.values(cols).filter(Boolean);
};

const keyOptions = jabvoxTableName => [
  { value: '', label: t('JABVOX_DATA_EXPORT.MAP.NONE') },
  ...mappedCustomerColumns(jabvoxTableName).map(c => ({ value: c, label: c })),
];

const mappedCount = jabvoxTableName =>
  mappedCustomerColumns(jabvoxTableName).length;

// Set/clear a single jabvox column -> customer column mapping.
const setColumnMapping = (jabvoxTableName, jabvoxCol, customerCol) => {
  if (!map.value[jabvoxTableName]) {
    map.value[jabvoxTableName] = { key: '', columns: {} };
  }
  const entry = map.value[jabvoxTableName];
  if (customerCol) {
    entry.columns[jabvoxCol] = customerCol;
  } else {
    delete entry.columns[jabvoxCol];
  }
  // If the chosen key is no longer among mapped columns, drop it.
  if (
    entry.key &&
    !mappedCustomerColumns(jabvoxTableName).includes(entry.key)
  ) {
    entry.key = '';
  }
};

const setKey = (jabvoxTableName, customerCol) => {
  if (!map.value[jabvoxTableName]) {
    map.value[jabvoxTableName] = { key: '', columns: {} };
  }
  map.value[jabvoxTableName].key = customerCol;
};

const columnMapValue = (jabvoxTableName, jabvoxCol) =>
  map.value[jabvoxTableName]?.columns?.[jabvoxCol] || '';

const keyValue = jabvoxTableName => map.value[jabvoxTableName]?.key || '';

// Auto-propose mappings for columns whose name matches on both sides, and pick
// a sensible key ('id_jabvox' or 'id') when present on the customer table.
const proposeMapping = () => {
  jabvoxTables.value.forEach(jt => {
    const rt = remoteTableFor(jt.table);
    if (!rt) return;
    const remoteNames = rt.columns.map(c => c.name);
    const entry = { key: '', columns: {} };
    jt.columns.forEach(jc => {
      if (remoteNames.includes(jc)) entry.columns[jc] = jc;
    });
    const mapped = Object.values(entry.columns);
    if (mapped.includes('id_jabvox')) entry.key = 'id_jabvox';
    else if (mapped.includes('id')) entry.key = 'id';
    if (Object.keys(entry.columns).length) map.value[jt.table] = entry;
  });
};

const detectSchema = async () => {
  detecting.value = true;
  try {
    const { data } = await dataExportAPI.remoteSchema(target.value.id);
    remoteTables.value = data.remote_tables || [];
    jabvoxTables.value = data.jabvox_tables || [];
    // Seed from any previously saved mapping, otherwise auto-propose.
    if (
      target.value.field_mapping_jabvox &&
      Object.keys(target.value.field_mapping_jabvox).length
    ) {
      map.value = JSON.parse(JSON.stringify(target.value.field_mapping_jabvox));
    } else {
      map.value = {};
      proposeMapping();
    }
    createMissing.value = !!target.value.create_missing_columns_jabvox;
    schemaLoaded.value = true;
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SCHEMA_ERROR'));
  } finally {
    detecting.value = false;
  }
};

const saveMapping = async () => {
  // Only keep tables with at least one mapped column AND a chosen key.
  const fieldMapping = {};
  Object.entries(map.value).forEach(([table, entry]) => {
    const columns = Object.fromEntries(
      Object.entries(entry.columns || {}).filter(([, v]) => v)
    );
    if (Object.keys(columns).length && entry.key) {
      fieldMapping[table] = { key: entry.key, columns };
    }
  });
  savingMapping.value = true;
  try {
    await dataExportAPI.saveMapping(target.value.id, {
      mode_jabvox: 'map',
      create_missing_columns_jabvox: createMissing.value,
      field_mapping_jabvox: fieldMapping,
    });
    await load();
    useAlert(t('JABVOX_DATA_EXPORT.MAP.SAVED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SAVE_ERROR'));
  } finally {
    savingMapping.value = false;
  }
};

// ---------- Sync ----------
const syncStatusLabel = computed(() => {
  const s = target.value?.sync_status_jabvox || 'idle';
  return t(`JABVOX_DATA_EXPORT.SYNC.${s.toUpperCase()}`);
});

const syncNow = async () => {
  syncing.value = true;
  try {
    await dataExportAPI.syncNow(target.value.id);
    await load();
    useAlert(t('JABVOX_DATA_EXPORT.SYNC.QUEUED'));
  } catch (e) {
    useAlert(apiError(e, 'JABVOX_DATA_EXPORT.SAVE_ERROR'));
  } finally {
    syncing.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col flex-1 overflow-auto bg-n-background">
    <div class="w-full max-w-[900px] mx-auto px-6 py-8 flex flex-col gap-6">
      <header>
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ t('JABVOX_DATA_EXPORT.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('JABVOX_DATA_EXPORT.SUBTITLE') }}
        </p>
      </header>

      <!-- Connection form -->
      <section
        v-if="editing"
        class="rounded-2xl bg-n-solid-1 border border-n-weak p-6 flex flex-col gap-4"
      >
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{
            editing.id
              ? t('JABVOX_DATA_EXPORT.FORM.EDIT_TITLE')
              : t('JABVOX_DATA_EXPORT.FORM.NEW_TITLE')
          }}
        </h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="editing.name_jabvox"
            :label="t('JABVOX_DATA_EXPORT.FORM.NAME')"
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DATA_EXPORT.FORM.ENGINE') }}
            </label>
            <Select v-model="editing.engine_jabvox" :options="engineOptions" />
          </div>
          <Input
            v-model="editing.host_jabvox"
            :label="t('JABVOX_DATA_EXPORT.FORM.HOST')"
          />
          <Input
            v-model="editing.port_jabvox"
            type="number"
            :label="t('JABVOX_DATA_EXPORT.FORM.PORT')"
          />
          <Input
            v-model="editing.database_jabvox"
            :label="t('JABVOX_DATA_EXPORT.FORM.DATABASE')"
          />
          <Input
            v-model="editing.username_jabvox"
            :label="t('JABVOX_DATA_EXPORT.FORM.USERNAME')"
          />
          <Input
            v-model="editing.password_jabvox"
            type="password"
            :label="t('JABVOX_DATA_EXPORT.FORM.PASSWORD')"
            :placeholder="
              editing.has_password
                ? t('JABVOX_DATA_EXPORT.FORM.PASSWORD_KEEP')
                : ''
            "
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DATA_EXPORT.MODE.LABEL') }}
            </label>
            <Select v-model="editing.mode_jabvox" :options="modeOptions" />
          </div>
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
            :label="t('JABVOX_DATA_EXPORT.FORM.TEST')"
            variant="outline"
            color="slate"
            :is-loading="testing"
            @click="testConnection"
          />
          <Button
            class="ml-auto"
            :label="t('JABVOX_DATA_EXPORT.FORM.SAVE')"
            @click="save"
          />
          <Button
            :label="t('JABVOX_DATA_EXPORT.FORM.CANCEL')"
            variant="ghost"
            color="slate"
            @click="cancelEdit"
          />
        </div>
      </section>

      <!-- No connection yet -->
      <section
        v-else-if="!target"
        class="rounded-2xl border border-dashed border-n-weak p-10 text-center flex flex-col items-center gap-3"
      >
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_DATA_EXPORT.EMPTY') }}
        </p>
        <Button
          :label="t('JABVOX_DATA_EXPORT.NEW')"
          icon="i-lucide-plus"
          @click="openNew"
        />
      </section>

      <!-- Connected -->
      <section
        v-else
        class="rounded-2xl bg-n-solid-1 border border-n-weak p-6 flex flex-col gap-4"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="text-base font-semibold text-n-slate-12">
              {{ target.name_jabvox }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ target.engine_jabvox }} · {{ target.host_jabvox }} ·
              {{ target.database_jabvox }}
            </p>
          </div>
          <label class="flex items-center gap-2 shrink-0">
            <span class="text-sm text-n-slate-11">
              {{ t('JABVOX_DATA_EXPORT.ENABLED') }}
            </span>
            <Switch
              :model-value="target.enabled_jabvox"
              @update:model-value="toggleEnabled"
            />
          </label>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
          <div>
            <p class="text-n-slate-10 text-xs">
              {{ t('JABVOX_DATA_EXPORT.STATUS') }}
            </p>
            <p class="text-n-slate-12">{{ target.status_jabvox }}</p>
          </div>
          <div>
            <p class="text-n-slate-10 text-xs">
              {{ t('JABVOX_DATA_EXPORT.SCHEMA') }}
            </p>
            <p class="text-n-slate-12">
              {{
                target.schema_built_at_jabvox
                  ? t('JABVOX_DATA_EXPORT.SCHEMA_READY')
                  : t('JABVOX_DATA_EXPORT.SCHEMA_PENDING')
              }}
            </p>
          </div>
          <div>
            <p class="text-n-slate-10 text-xs">
              {{ t('JABVOX_DATA_EXPORT.LAST_EXPORT') }}
            </p>
            <p class="text-n-slate-12">
              {{ target.last_export_at_jabvox || '—' }}
            </p>
          </div>
          <div v-if="target.last_error_jabvox">
            <p class="text-n-slate-10 text-xs">
              {{ t('JABVOX_DATA_EXPORT.LAST_ERROR') }}
            </p>
            <p class="text-n-ruby-11">{{ target.last_error_jabvox }}</p>
          </div>
        </div>

        <div
          class="flex flex-wrap items-center gap-2 pt-2 border-t border-n-weak"
        >
          <Button
            :label="t('JABVOX_DATA_EXPORT.FORM.TEST')"
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-plug-zap"
            :is-loading="testing"
            @click="testSaved"
          />
          <Button
            v-if="target.mode_jabvox !== 'map'"
            :label="t('JABVOX_DATA_EXPORT.BUILD_SCHEMA')"
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-table"
            :is-loading="building"
            @click="buildSchema"
          />
          <Button
            :label="t('JABVOX_DATA_EXPORT.FORM.EDIT')"
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-pencil"
            @click="openEdit"
          />
          <Button
            class="ml-auto"
            :label="t('JABVOX_DATA_EXPORT.DELETE')"
            variant="ghost"
            color="ruby"
            size="sm"
            icon="i-lucide-trash-2"
            @click="remove"
          />
        </div>

        <!-- ============ FIELD MAPPING (map mode) ============ -->
        <div
          v-if="target.mode_jabvox === 'map'"
          class="flex flex-col gap-4 pt-2 border-t border-n-weak"
        >
          <div class="flex items-center justify-between gap-4">
            <div>
              <h3 class="text-base font-semibold text-n-slate-12">
                {{ t('JABVOX_DATA_EXPORT.MAP.TITLE') }}
              </h3>
            </div>
            <Button
              :label="
                detecting
                  ? t('JABVOX_DATA_EXPORT.MAP.DETECTING')
                  : t('JABVOX_DATA_EXPORT.MAP.DETECT')
              "
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-search"
              :is-loading="detecting"
              @click="detectSchema"
            />
          </div>

          <div
            v-if="detecting"
            class="flex items-center gap-2 text-sm text-n-slate-11"
          >
            <Spinner :size="16" />
            {{ t('JABVOX_DATA_EXPORT.MAP.DETECTING') }}
          </div>

          <template v-else-if="schemaLoaded">
            <label class="flex items-center gap-2">
              <Switch v-model="createMissing" />
              <span class="text-sm text-n-slate-12">
                {{ t('JABVOX_DATA_EXPORT.MAP.CREATE_MISSING') }}
              </span>
            </label>

            <div
              v-for="jt in jabvoxTables"
              :key="jt.table"
              class="rounded-xl border border-n-weak p-4 flex flex-col gap-3"
            >
              <div class="flex items-center justify-between gap-2">
                <p class="text-sm font-semibold text-n-slate-12 font-mono">
                  {{ jt.table }}
                </p>
                <span
                  class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium bg-n-teal-3 text-n-teal-11"
                >
                  {{
                    t('JABVOX_DATA_EXPORT.MAP.MAPPED_COUNT', {
                      count: mappedCount(jt.table),
                    })
                  }}
                </span>
              </div>

              <p
                v-if="!remoteTableFor(jt.table) && !createMissing"
                class="text-xs rounded-lg px-3 py-2 bg-n-amber-3 text-n-amber-11"
              >
                {{ t('JABVOX_DATA_EXPORT.MAP.NO_REMOTE_TABLE') }}
              </p>
              <p
                v-else-if="!remoteTableFor(jt.table)"
                class="text-xs text-n-amber-11"
              >
                {{ t('JABVOX_DATA_EXPORT.MAP.NO_REMOTE_TABLE') }}
              </p>

              <div class="flex flex-col divide-y divide-n-weak">
                <div
                  v-for="jc in jt.columns"
                  :key="jc"
                  class="grid grid-cols-[1fr_1fr] gap-3 items-center py-2 text-sm"
                >
                  <span class="text-n-slate-12 font-mono truncate">{{
                    jc
                  }}</span>
                  <ComboBox
                    :model-value="columnMapValue(jt.table, jc)"
                    :options="customerColumnOptions(jt.table)"
                    :disabled="!remoteTableFor(jt.table) && !createMissing"
                    :placeholder="t('JABVOX_DATA_EXPORT.MAP.CUSTOMER_COLUMN')"
                    @update:model-value="setColumnMapping(jt.table, jc, $event)"
                  />
                </div>
              </div>

              <div v-if="mappedCount(jt.table)" class="flex flex-col gap-1.5">
                <label class="text-xs font-medium text-n-slate-12">
                  {{ t('JABVOX_DATA_EXPORT.MAP.KEY') }}
                </label>
                <ComboBox
                  :model-value="keyValue(jt.table)"
                  :options="keyOptions(jt.table)"
                  :placeholder="t('JABVOX_DATA_EXPORT.MAP.KEY')"
                  @update:model-value="setKey(jt.table, $event)"
                />
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_DATA_EXPORT.MAP.KEY_HINT') }}
                </p>
              </div>
            </div>

            <div class="flex justify-end">
              <Button
                :label="t('JABVOX_DATA_EXPORT.MAP.SAVE')"
                icon="i-lucide-save"
                :is-loading="savingMapping"
                @click="saveMapping"
              />
            </div>
          </template>
        </div>

        <!-- ============ SYNC (both modes) ============ -->
        <div class="flex flex-col gap-3 pt-2 border-t border-n-weak">
          <div class="flex items-center justify-between gap-4">
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_DATA_EXPORT.SYNC.TITLE') }}
            </h3>
            <Button
              :label="t('JABVOX_DATA_EXPORT.SYNC.NOW')"
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-refresh-cw"
              :is-loading="syncing"
              @click="syncNow"
            />
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 text-sm">
            <div>
              <p class="text-n-slate-10 text-xs">
                {{ t('JABVOX_DATA_EXPORT.SYNC.STATUS') }}
              </p>
              <span
                class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium bg-n-alpha-1 text-n-slate-11"
              >
                {{ syncStatusLabel }}
              </span>
            </div>
            <div>
              <p class="text-n-slate-10 text-xs">
                {{ t('JABVOX_DATA_EXPORT.SYNC.LAST') }}
              </p>
              <p class="text-n-slate-12">
                {{ target.last_full_sync_at_jabvox || '—' }}
              </p>
            </div>
            <div v-if="target.last_sync_result_jabvox">
              <p class="text-n-slate-10 text-xs">
                {{ t('JABVOX_DATA_EXPORT.SYNC.EXPORTED') }} /
                {{ t('JABVOX_DATA_EXPORT.SYNC.FAILED') }}
              </p>
              <p class="text-n-slate-12">
                {{ target.last_sync_result_jabvox.exported || 0 }} /
                {{ target.last_sync_result_jabvox.failed || 0 }}
              </p>
            </div>
          </div>
        </div>

        <p class="text-xs text-n-slate-10">
          {{ t('JABVOX_DATA_EXPORT.DELETE_HINT') }}
        </p>
      </section>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="doRemove" />
  </div>
</template>
