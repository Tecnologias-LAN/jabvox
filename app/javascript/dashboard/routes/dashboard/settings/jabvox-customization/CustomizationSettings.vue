<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();
const showAlert = useAlert;

const tables = useMapGetter('jabvoxCustomization/getTables');
const buttons = useMapGetter('jabvoxCustomization/getButtons');
const uiFlags = useMapGetter('jabvoxCustomization/getUIFlags');

const COLUMN_TYPES = ['text', 'integer', 'float', 'boolean', 'date', 'select'];

const activeTab = ref('tables');

const tabs = [
  {
    key: 'tables',
    label: () => t('JABVOX_CUSTOMIZATION.TABS.TABLES'),
    icon: 'i-lucide-table',
  },
  {
    key: 'columns',
    label: () => t('JABVOX_CUSTOMIZATION.TABS.COLUMNS'),
    icon: 'i-lucide-columns',
  },
  {
    key: 'buttons',
    label: () => t('JABVOX_CUSTOMIZATION.TABS.BUTTONS'),
    icon: 'i-lucide-mouse-pointer-click',
  },
];

// ── Tables ────────────────────────────────────────────────────────────────────
const showNewTableForm = ref(false);
const expandedTableId = ref(null);
const deleteTableConfirmId = ref(null);

const emptyTableForm = () => ({ name_jabvox: '', description_jabvox: '' });
const newTableForm = ref(emptyTableForm());
const editTableForms = ref({});

const openTableEdit = table => {
  expandedTableId.value = expandedTableId.value === table.id ? null : table.id;
  if (!editTableForms.value[table.id]) {
    editTableForms.value[table.id] = {
      name_jabvox: table.name_jabvox,
      description_jabvox: table.description_jabvox || '',
      linked_to_jabvox: table.linked_to_jabvox || null,
    };
  }
};

const leadsTable = computed(
  () => tables.value.find(tbl => tbl.linked_to_jabvox === 'leads') || null
);

const toggleLeadsLink = async table => {
  const isCurrentlyLinked = table.linked_to_jabvox === 'leads';
  if (
    !isCurrentlyLinked &&
    leadsTable.value &&
    leadsTable.value.id !== table.id
  ) {
    showAlert(t('JABVOX_CUSTOMIZATION.TABLES.LEADS_LINK_CONFLICT'));
    return;
  }
  try {
    await store.dispatch('jabvoxCustomization/updateTable', {
      id: table.id,
      linked_to_jabvox: isCurrentlyLinked ? null : 'leads',
    });
    showAlert(t('JABVOX_CUSTOMIZATION.TABLES.SAVE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const saveNewTable = async () => {
  try {
    await store.dispatch('jabvoxCustomization/createTable', newTableForm.value);
    newTableForm.value = emptyTableForm();
    showNewTableForm.value = false;
    showAlert(t('JABVOX_CUSTOMIZATION.TABLES.SAVE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const saveEditTable = async id => {
  try {
    await store.dispatch('jabvoxCustomization/updateTable', {
      id,
      ...editTableForms.value[id],
    });
    expandedTableId.value = null;
    showAlert(t('JABVOX_CUSTOMIZATION.TABLES.SAVE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const confirmDeleteTable = id => {
  deleteTableConfirmId.value = id;
};

const doDeleteTable = async id => {
  try {
    await store.dispatch('jabvoxCustomization/deleteTable', id);
    deleteTableConfirmId.value = null;
    showAlert(t('JABVOX_CUSTOMIZATION.TABLES.DELETE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

// ── Columns ───────────────────────────────────────────────────────────────────
const selectedTableId = ref(null);
const showNewColumnForm = ref(false);
const expandedColumnId = ref(null);
const deleteColumnConfirmId = ref(null);

const selectedTable = computed(() =>
  tables.value.find(tbl => tbl.id === selectedTableId.value)
);
const selectedTableColumns = computed(() => selectedTable.value?.columns || []);

// The "Leads" system table is always present in `tables` (the backend ensures
// it exists), so the column selector just lists every table. Leads is shown
// first and labelled distinctly. Columns added to it are the lead's custom fields.
const onSelectTable = value => {
  showNewColumnForm.value = false;
  expandedColumnId.value = null;
  selectedTableId.value = value ? Number(value) : null;
};

// Leads first, then the rest, for the selector dropdown.
const sortedTables = computed(() => {
  const leads = tables.value.filter(tbl => tbl.linked_to_jabvox === 'leads');
  const rest = tables.value.filter(tbl => tbl.linked_to_jabvox !== 'leads');
  return [...leads, ...rest];
});

const emptyColumnForm = () => ({
  name_jabvox: '',
  label_jabvox: '',
  column_type_jabvox: 'text',
  required_jabvox: false,
  options_jabvox: [],
  options_text: '',
});
const newColumnForm = ref(emptyColumnForm());
const editColumnForms = ref({});

const openColumnEdit = col => {
  expandedColumnId.value = expandedColumnId.value === col.id ? null : col.id;
  if (!editColumnForms.value[col.id]) {
    editColumnForms.value[col.id] = {
      name_jabvox: col.name_jabvox,
      label_jabvox: col.label_jabvox,
      column_type_jabvox: col.column_type_jabvox,
      required_jabvox: col.required_jabvox,
      options_jabvox: col.options_jabvox || [],
      options_text: (col.options_jabvox || []).join(', '),
    };
  }
};

const parseOptions = text =>
  text
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

const saveNewColumn = async () => {
  if (!selectedTableId.value) return;
  try {
    const payload = { ...newColumnForm.value };
    if (payload.column_type_jabvox === 'select') {
      payload.options_jabvox = parseOptions(payload.options_text);
    }
    delete payload.options_text;
    await store.dispatch('jabvoxCustomization/createColumn', {
      tableId: selectedTableId.value,
      ...payload,
    });
    newColumnForm.value = emptyColumnForm();
    showNewColumnForm.value = false;
    showAlert(t('JABVOX_CUSTOMIZATION.COLUMNS.SAVE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const saveEditColumn = async id => {
  const form = editColumnForms.value[id];
  try {
    const payload = { ...form };
    if (payload.column_type_jabvox === 'select') {
      payload.options_jabvox = parseOptions(payload.options_text);
    }
    delete payload.options_text;
    await store.dispatch('jabvoxCustomization/updateColumn', {
      tableId: selectedTableId.value,
      id,
      ...payload,
    });
    expandedColumnId.value = null;
    showAlert(t('JABVOX_CUSTOMIZATION.COLUMNS.SAVE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const confirmDeleteColumn = id => {
  deleteColumnConfirmId.value = id;
};

const doDeleteColumn = async id => {
  try {
    await store.dispatch('jabvoxCustomization/deleteColumn', {
      tableId: selectedTableId.value,
      id,
    });
    deleteColumnConfirmId.value = null;
    showAlert(t('JABVOX_CUSTOMIZATION.COLUMNS.DELETE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

// ── Buttons ───────────────────────────────────────────────────────────────────
const showNewButtonForm = ref(false);
const expandedButtonId = ref(null);
const deleteButtonConfirmId = ref(null);

const BUTTON_COLORS = [
  '#6b7280',
  '#3b82f6',
  '#10b981',
  '#f59e0b',
  '#ef4444',
  '#8b5cf6',
  '#ec4899',
  '#06b6d4',
  '#84cc16',
  '#f97316',
];

const emptyButtonForm = () => ({
  name_jabvox: '',
  url_jabvox: '',
  color_jabvox: '#6b7280',
  active_jabvox: true,
});
const newButtonForm = ref(emptyButtonForm());
const editButtonForms = ref({});

const openButtonEdit = btn => {
  expandedButtonId.value = expandedButtonId.value === btn.id ? null : btn.id;
  if (!editButtonForms.value[btn.id]) {
    editButtonForms.value[btn.id] = {
      name_jabvox: btn.name_jabvox,
      url_jabvox: btn.url_jabvox,
      color_jabvox: btn.color_jabvox,
      active_jabvox: btn.active_jabvox,
    };
  }
};

const saveNewButton = async () => {
  try {
    await store.dispatch(
      'jabvoxCustomization/createButton',
      newButtonForm.value
    );
    newButtonForm.value = emptyButtonForm();
    showNewButtonForm.value = false;
    showAlert(t('JABVOX_CUSTOMIZATION.BUTTONS.SAVE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const saveEditButton = async id => {
  try {
    await store.dispatch('jabvoxCustomization/updateButton', {
      id,
      ...editButtonForms.value[id],
    });
    expandedButtonId.value = null;
    showAlert(t('JABVOX_CUSTOMIZATION.BUTTONS.SAVE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const confirmDeleteButton = id => {
  deleteButtonConfirmId.value = id;
};

const doDeleteButton = async id => {
  try {
    await store.dispatch('jabvoxCustomization/deleteButton', id);
    deleteButtonConfirmId.value = null;
    showAlert(t('JABVOX_CUSTOMIZATION.BUTTONS.DELETE_SUCCESS'));
  } catch {
    showAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

onMounted(async () => {
  await Promise.all([
    store.dispatch('jabvoxCustomization/fetchTables'),
    store.dispatch('jabvoxCustomization/fetchButtons'),
  ]);
});
</script>

<template>
  <div class="flex flex-col gap-6 p-6 max-w-5xl">
    <!-- Header -->
    <div>
      <h1 class="text-xl font-semibold text-slate-900 dark:text-slate-100">
        {{ t('JABVOX_CUSTOMIZATION.SETTINGS.TITLE') }}
      </h1>
      <p class="text-sm text-slate-500 mt-1">
        {{ t('JABVOX_CUSTOMIZATION.SETTINGS.SUBTITLE') }}
      </p>
    </div>

    <!-- Tabs -->
    <div class="flex gap-1 border-b border-slate-200 dark:border-slate-700">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        class="flex items-center gap-2 px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px"
        :class="
          activeTab === tab.key
            ? 'border-woot-500 text-woot-600 dark:text-woot-400'
            : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300'
        "
        @click="activeTab = tab.key"
      >
        <span :class="tab.icon" class="size-4" />
        {{ tab.label() }}
      </button>
    </div>

    <!-- ── TABLES TAB ── -->
    <div v-if="activeTab === 'tables'" class="flex flex-col gap-4">
      <div class="flex items-center justify-between">
        <p class="text-sm text-slate-500">
          {{ t('JABVOX_CUSTOMIZATION.TABLES.DESCRIPTION') }}
        </p>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.TABLES.NEW')"
          size="sm"
          @click="showNewTableForm = true"
        />
      </div>

      <!-- New table form -->
      <div
        v-if="showNewTableForm"
        class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4 flex flex-col gap-3"
      >
        <p class="text-sm font-medium text-slate-700 dark:text-slate-300">
          {{ t('JABVOX_CUSTOMIZATION.TABLES.NEW') }}
        </p>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('JABVOX_CUSTOMIZATION.TABLES.NAME_LABEL') }}
            </label>
            <input
              v-model="newTableForm.name_jabvox"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="t('JABVOX_CUSTOMIZATION.TABLES.NAME_PLACEHOLDER')"
            />
          </div>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('JABVOX_CUSTOMIZATION.TABLES.DESCRIPTION_LABEL') }}
            </label>
            <input
              v-model="newTableForm.description_jabvox"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="
                t('JABVOX_CUSTOMIZATION.TABLES.DESCRIPTION_PLACEHOLDER')
              "
            />
          </div>
        </div>
        <div class="flex gap-2 justify-end">
          <Button
            variant="ghost"
            size="sm"
            :label="t('JABVOX_CUSTOMIZATION.TABLES.CANCEL')"
            @click="
              showNewTableForm = false;
              newTableForm = emptyTableForm();
            "
          />
          <Button
            size="sm"
            :label="t('JABVOX_CUSTOMIZATION.TABLES.SAVE')"
            :is-loading="uiFlags.isSaving"
            @click="saveNewTable"
          />
        </div>
      </div>

      <!-- Tables list -->
      <div
        v-if="uiFlags.isFetchingTables"
        class="text-sm text-slate-400 py-8 text-center"
      >
        {{ t('JABVOX_CUSTOMIZATION.LOADING') }}
      </div>
      <div
        v-else-if="!tables.length"
        class="text-sm text-slate-400 py-8 text-center border border-dashed border-slate-200 dark:border-slate-700 rounded-xl"
      >
        {{ t('JABVOX_CUSTOMIZATION.TABLES.EMPTY') }}
      </div>
      <div v-else class="flex flex-col gap-2">
        <div
          v-for="table in tables"
          :key="table.id"
          class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 overflow-hidden"
        >
          <div class="flex items-center justify-between p-4">
            <div>
              <div class="flex items-center gap-2">
                <p
                  class="text-sm font-medium text-slate-800 dark:text-slate-200"
                >
                  {{ table.name_jabvox }}
                </p>
                <span
                  v-if="table.linked_to_jabvox === 'leads'"
                  class="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300"
                >
                  <span class="i-lucide-user size-3" />
                  {{ t('JABVOX_CUSTOMIZATION.COLUMNS.LEADS_HINT') }}
                </span>
              </div>
              <p
                v-if="table.description_jabvox"
                class="text-xs text-slate-500 mt-0.5"
              >
                {{ table.description_jabvox }}
              </p>
              <p class="text-xs text-slate-400 mt-0.5">
                {{ (table.columns || []).length }}
                {{
                  (table.columns || []).length === 1 ? 'columna' : 'columnas'
                }}
              </p>
            </div>
            <!-- System table (Leads): read-only, no edit/delete -->
            <div
              v-if="table.system"
              class="flex items-center gap-1 text-xs text-slate-400"
              :title="t('JABVOX_CUSTOMIZATION.TABLES.SYSTEM_TABLE')"
            >
              <span class="i-lucide-lock size-4" />
              {{ t('JABVOX_CUSTOMIZATION.TABLES.SYSTEM') }}
            </div>
            <div v-else class="flex items-center gap-2">
              <button
                :title="
                  table.linked_to_jabvox === 'leads'
                    ? 'Quitar como campos del lead'
                    : 'Usar como campos del lead'
                "
                class="text-slate-400 hover:text-indigo-600 transition-colors"
                :class="
                  table.linked_to_jabvox === 'leads' ? 'text-indigo-600' : ''
                "
                @click="toggleLeadsLink(table)"
              >
                <span class="i-lucide-user size-4" />
              </button>
              <button
                class="text-slate-400 hover:text-woot-600 transition-colors"
                @click="openTableEdit(table)"
              >
                <span class="i-lucide-pencil size-4" />
              </button>
              <button
                class="text-slate-400 hover:text-red-500 transition-colors"
                @click="confirmDeleteTable(table.id)"
              >
                <span class="i-lucide-trash-2 size-4" />
              </button>
            </div>
          </div>

          <!-- Edit form -->
          <div
            v-if="expandedTableId === table.id"
            class="border-t border-slate-100 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 p-4 flex flex-col gap-3"
          >
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                >
                  {{ t('JABVOX_CUSTOMIZATION.TABLES.NAME_LABEL') }}
                </label>
                <input
                  v-model="editTableForms[table.id].name_jabvox"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                >
                  {{ t('JABVOX_CUSTOMIZATION.TABLES.DESCRIPTION_LABEL') }}
                </label>
                <input
                  v-model="editTableForms[table.id].description_jabvox"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>
            </div>
            <div class="flex gap-2 justify-end">
              <Button
                variant="ghost"
                size="sm"
                :label="t('JABVOX_CUSTOMIZATION.TABLES.CANCEL')"
                @click="expandedTableId = null"
              />
              <Button
                size="sm"
                :label="t('JABVOX_CUSTOMIZATION.TABLES.SAVE')"
                :is-loading="uiFlags.isSaving"
                @click="saveEditTable(table.id)"
              />
            </div>
          </div>

          <!-- Delete confirm -->
          <div
            v-if="deleteTableConfirmId === table.id"
            class="border-t border-red-100 bg-red-50 dark:bg-red-900/20 p-4 flex items-center justify-between gap-3"
          >
            <p class="text-sm text-red-700 dark:text-red-300">
              {{
                t('JABVOX_CUSTOMIZATION.TABLES.DELETE_CONFIRM', {
                  name: table.name_jabvox,
                })
              }}
            </p>
            <div class="flex gap-2">
              <Button
                variant="ghost"
                size="sm"
                :label="t('JABVOX_CUSTOMIZATION.TABLES.CANCEL')"
                @click="deleteTableConfirmId = null"
              />
              <Button
                variant="destructive"
                size="sm"
                :label="t('JABVOX_CUSTOMIZATION.TABLES.DELETE')"
                @click="doDeleteTable(table.id)"
              />
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ── COLUMNS TAB ── -->
    <div v-if="activeTab === 'columns'" class="flex flex-col gap-4">
      <p class="text-sm text-slate-500">
        {{ t('JABVOX_CUSTOMIZATION.COLUMNS.DESCRIPTION') }}
      </p>

      <!-- Table selector -->
      <div>
        <label
          class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
        >
          {{ t('JABVOX_CUSTOMIZATION.COLUMNS.SELECT_TABLE') }}
        </label>
        <select
          :value="selectedTableId"
          class="w-full max-w-sm rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
          @change="onSelectTable($event.target.value)"
        >
          <option :value="null">
            {{ t('JABVOX_CUSTOMIZATION.COLUMNS.SELECT_TABLE_PLACEHOLDER') }}
          </option>
          <!-- Leads first, then custom tables -->
          <option v-for="tbl in sortedTables" :key="tbl.id" :value="tbl.id">
            {{
              tbl.linked_to_jabvox === 'leads'
                ? t('JABVOX_CUSTOMIZATION.COLUMNS.LEADS_OPTION')
                : tbl.name_jabvox
            }}
          </option>
        </select>
      </div>

      <div
        v-if="!selectedTableId"
        class="text-sm text-slate-400 py-8 text-center border border-dashed border-slate-200 dark:border-slate-700 rounded-xl"
      >
        {{ t('JABVOX_CUSTOMIZATION.COLUMNS.NO_TABLE_SELECTED') }}
      </div>

      <template v-else>
        <div class="flex items-center justify-between">
          <p
            class="text-sm font-medium text-slate-700 dark:text-slate-300 flex items-center gap-2"
          >
            <span
              v-if="selectedTable?.linked_to_jabvox === 'leads'"
              class="inline-flex items-center gap-1"
            >
              <span class="i-lucide-users size-4 text-woot-500" />
              {{ t('JABVOX_CUSTOMIZATION.COLUMNS.LEADS_OPTION') }}
            </span>
            <span v-else>{{ selectedTable?.name_jabvox }}</span>
            <span
              v-if="selectedTable?.linked_to_jabvox === 'leads'"
              class="text-xs font-normal text-slate-400"
            >
              {{ t('JABVOX_CUSTOMIZATION.COLUMNS.LEADS_HINT') }}
            </span>
          </p>
          <Button
            icon="i-lucide-plus"
            :label="t('JABVOX_CUSTOMIZATION.COLUMNS.NEW')"
            size="sm"
            @click="showNewColumnForm = true"
          />
        </div>

        <!-- New column form -->
        <div
          v-if="showNewColumnForm"
          class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4 flex flex-col gap-3"
        >
          <div class="grid grid-cols-3 gap-3">
            <div>
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >
                {{ t('JABVOX_CUSTOMIZATION.COLUMNS.INTERNAL_NAME_LABEL') }}
              </label>
              <input
                v-model="newColumnForm.name_jabvox"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                :placeholder="
                  t('JABVOX_CUSTOMIZATION.COLUMNS.INTERNAL_NAME_PLACEHOLDER')
                "
              />
              <p class="text-xs text-slate-400 mt-0.5">
                {{ t('JABVOX_CUSTOMIZATION.COLUMNS.INTERNAL_NAME_HINT') }}
              </p>
            </div>
            <div>
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >
                {{ t('JABVOX_CUSTOMIZATION.COLUMNS.DISPLAY_LABEL') }}
              </label>
              <input
                v-model="newColumnForm.label_jabvox"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                :placeholder="
                  t('JABVOX_CUSTOMIZATION.COLUMNS.DISPLAY_PLACEHOLDER')
                "
              />
            </div>
            <div>
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >
                {{ t('JABVOX_CUSTOMIZATION.COLUMNS.TYPE_LABEL') }}
              </label>
              <select
                v-model="newColumnForm.column_type_jabvox"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
              >
                <option v-for="type in COLUMN_TYPES" :key="type" :value="type">
                  {{ t(`JABVOX_CUSTOMIZATION.COLUMNS.TYPES.${type}`) }}
                </option>
              </select>
            </div>
          </div>
          <div v-if="newColumnForm.column_type_jabvox === 'select'">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('JABVOX_CUSTOMIZATION.COLUMNS.OPTIONS_LABEL') }}
            </label>
            <input
              v-model="newColumnForm.options_text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="
                t('JABVOX_CUSTOMIZATION.COLUMNS.OPTIONS_PLACEHOLDER')
              "
            />
          </div>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              v-model="newColumnForm.required_jabvox"
              type="checkbox"
              class="rounded border-slate-300"
            />
            <span class="text-sm text-slate-700 dark:text-slate-300">{{
              t('JABVOX_CUSTOMIZATION.COLUMNS.REQUIRED_LABEL')
            }}</span>
          </label>
          <div class="flex gap-2 justify-end">
            <Button
              variant="ghost"
              size="sm"
              :label="t('JABVOX_CUSTOMIZATION.COLUMNS.CANCEL')"
              @click="
                showNewColumnForm = false;
                newColumnForm = emptyColumnForm();
              "
            />
            <Button
              size="sm"
              :label="t('JABVOX_CUSTOMIZATION.COLUMNS.SAVE')"
              @click="saveNewColumn"
            />
          </div>
        </div>

        <!-- Columns list -->
        <div
          v-if="!selectedTableColumns.length"
          class="text-sm text-slate-400 py-8 text-center border border-dashed border-slate-200 dark:border-slate-700 rounded-xl"
        >
          {{ t('JABVOX_CUSTOMIZATION.COLUMNS.EMPTY') }}
        </div>
        <div v-else class="flex flex-col gap-2">
          <div
            v-for="col in selectedTableColumns"
            :key="col.id"
            class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 overflow-hidden"
          >
            <div class="flex items-center justify-between p-3">
              <div class="flex items-center gap-3">
                <span
                  class="text-xs px-2 py-0.5 rounded-full bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 font-mono"
                >
                  {{ col.name_jabvox }}
                </span>
                <span class="text-sm text-slate-700 dark:text-slate-300">{{
                  col.label_jabvox
                }}</span>
                <span class="text-xs text-slate-400">{{
                  t(
                    `JABVOX_CUSTOMIZATION.COLUMNS.TYPES.${col.column_type_jabvox}`
                  )
                }}</span>
                <span v-if="col.required_jabvox" class="text-xs text-red-500">
                  *
                </span>
              </div>
              <div class="flex items-center gap-2">
                <button
                  class="text-slate-400 hover:text-woot-600"
                  @click="openColumnEdit(col)"
                >
                  <span class="i-lucide-pencil size-4" />
                </button>
                <button
                  class="text-slate-400 hover:text-red-500"
                  @click="confirmDeleteColumn(col.id)"
                >
                  <span class="i-lucide-trash-2 size-4" />
                </button>
              </div>
            </div>

            <!-- Edit form -->
            <div
              v-if="expandedColumnId === col.id"
              class="border-t border-slate-100 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 p-4 flex flex-col gap-3"
            >
              <div class="grid grid-cols-3 gap-3">
                <div>
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                    >{{
                      t('JABVOX_CUSTOMIZATION.COLUMNS.INTERNAL_NAME_LABEL')
                    }}</label
                  >
                  <input
                    v-model="editColumnForms[col.id].name_jabvox"
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
                <div>
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                    >{{
                      t('JABVOX_CUSTOMIZATION.COLUMNS.DISPLAY_LABEL')
                    }}</label
                  >
                  <input
                    v-model="editColumnForms[col.id].label_jabvox"
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                  />
                </div>
                <div>
                  <label
                    class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                    >{{ t('JABVOX_CUSTOMIZATION.COLUMNS.TYPE_LABEL') }}</label
                  >
                  <select
                    v-model="editColumnForms[col.id].column_type_jabvox"
                    class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                  >
                    <option
                      v-for="type in COLUMN_TYPES"
                      :key="type"
                      :value="type"
                    >
                      {{ t(`JABVOX_CUSTOMIZATION.COLUMNS.TYPES.${type}`) }}
                    </option>
                  </select>
                </div>
              </div>
              <div
                v-if="editColumnForms[col.id].column_type_jabvox === 'select'"
              >
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >{{ t('JABVOX_CUSTOMIZATION.COLUMNS.OPTIONS_LABEL') }}</label
                >
                <input
                  v-model="editColumnForms[col.id].options_text"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                  :placeholder="
                    t('JABVOX_CUSTOMIZATION.COLUMNS.OPTIONS_PLACEHOLDER')
                  "
                />
              </div>
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  v-model="editColumnForms[col.id].required_jabvox"
                  type="checkbox"
                  class="rounded border-slate-300"
                />
                <span class="text-sm text-slate-700 dark:text-slate-300">{{
                  t('JABVOX_CUSTOMIZATION.COLUMNS.REQUIRED_LABEL')
                }}</span>
              </label>
              <div class="flex gap-2 justify-end">
                <Button
                  variant="ghost"
                  size="sm"
                  :label="t('JABVOX_CUSTOMIZATION.COLUMNS.CANCEL')"
                  @click="expandedColumnId = null"
                />
                <Button
                  size="sm"
                  :label="t('JABVOX_CUSTOMIZATION.COLUMNS.SAVE')"
                  @click="saveEditColumn(col.id)"
                />
              </div>
            </div>

            <!-- Delete confirm -->
            <div
              v-if="deleteColumnConfirmId === col.id"
              class="border-t border-red-100 bg-red-50 dark:bg-red-900/20 p-3 flex items-center justify-between gap-3"
            >
              <p class="text-sm text-red-700 dark:text-red-300">
                {{
                  t('JABVOX_CUSTOMIZATION.COLUMNS.DELETE_CONFIRM', {
                    name: col.label_jabvox,
                  })
                }}
              </p>
              <div class="flex gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  :label="t('JABVOX_CUSTOMIZATION.COLUMNS.CANCEL')"
                  @click="deleteColumnConfirmId = null"
                />
                <Button
                  variant="destructive"
                  size="sm"
                  :label="t('JABVOX_CUSTOMIZATION.COLUMNS.DELETE')"
                  @click="doDeleteColumn(col.id)"
                />
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- ── BUTTONS TAB ── -->
    <div v-if="activeTab === 'buttons'" class="flex flex-col gap-4">
      <div class="flex items-center justify-between">
        <p class="text-sm text-slate-500">
          {{ t('JABVOX_CUSTOMIZATION.BUTTONS.DESCRIPTION') }}
        </p>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.BUTTONS.NEW')"
          size="sm"
          @click="showNewButtonForm = true"
        />
      </div>

      <!-- New button form -->
      <div
        v-if="showNewButtonForm"
        class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4 flex flex-col gap-3"
      >
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ t('JABVOX_CUSTOMIZATION.BUTTONS.NAME_LABEL') }}</label
            >
            <input
              v-model="newButtonForm.name_jabvox"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="t('JABVOX_CUSTOMIZATION.BUTTONS.NAME_PLACEHOLDER')"
            />
          </div>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ t('JABVOX_CUSTOMIZATION.BUTTONS.URL_LABEL') }}</label
            >
            <input
              v-model="newButtonForm.url_jabvox"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="t('JABVOX_CUSTOMIZATION.BUTTONS.URL_PLACEHOLDER')"
            />
            <p class="text-xs text-slate-400 mt-0.5">
              {{ t('JABVOX_CUSTOMIZATION.BUTTONS.URL_HINT') }}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-4">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ t('JABVOX_CUSTOMIZATION.BUTTONS.COLOR_LABEL') }}</label
            >
            <div class="flex gap-2 flex-wrap">
              <button
                v-for="color in BUTTON_COLORS"
                :key="color"
                class="size-6 rounded-full border-2 transition-transform hover:scale-110"
                :style="{
                  backgroundColor: color,
                  borderColor:
                    newButtonForm.color_jabvox === color
                      ? color
                      : 'transparent',
                }"
                :class="
                  newButtonForm.color_jabvox === color
                    ? 'scale-110 shadow-md'
                    : ''
                "
                @click="newButtonForm.color_jabvox = color"
              />
            </div>
          </div>
          <label class="flex items-center gap-2 cursor-pointer ml-4">
            <input
              v-model="newButtonForm.active_jabvox"
              type="checkbox"
              class="rounded border-slate-300"
            />
            <span class="text-sm text-slate-700 dark:text-slate-300">{{
              t('JABVOX_CUSTOMIZATION.BUTTONS.ACTIVE_LABEL')
            }}</span>
          </label>
        </div>
        <div class="flex gap-2 justify-end">
          <Button
            variant="ghost"
            size="sm"
            :label="t('JABVOX_CUSTOMIZATION.BUTTONS.CANCEL')"
            @click="
              showNewButtonForm = false;
              newButtonForm = emptyButtonForm();
            "
          />
          <Button
            size="sm"
            :label="t('JABVOX_CUSTOMIZATION.BUTTONS.SAVE')"
            :is-loading="uiFlags.isSaving"
            @click="saveNewButton"
          />
        </div>
      </div>

      <!-- Buttons list -->
      <div
        v-if="uiFlags.isFetchingButtons"
        class="text-sm text-slate-400 py-8 text-center"
      >
        {{ t('JABVOX_CUSTOMIZATION.LOADING') }}
      </div>
      <div
        v-else-if="!buttons.length"
        class="text-sm text-slate-400 py-8 text-center border border-dashed border-slate-200 dark:border-slate-700 rounded-xl"
      >
        {{ t('JABVOX_CUSTOMIZATION.BUTTONS.EMPTY') }}
      </div>
      <div v-else class="flex flex-col gap-2">
        <div
          v-for="btn in buttons"
          :key="btn.id"
          class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 overflow-hidden"
        >
          <div class="flex items-center justify-between p-3">
            <div class="flex items-center gap-3">
              <span
                class="size-3 rounded-full inline-block"
                :style="{ backgroundColor: btn.color_jabvox }"
              />
              <span
                class="text-sm font-medium text-slate-800 dark:text-slate-200"
                >{{ btn.name_jabvox }}</span
              >
              <span
                class="text-xs text-slate-400 font-mono truncate max-w-xs"
                >{{ btn.url_jabvox }}</span
              >
              <span
                v-if="!btn.active_jabvox"
                class="text-xs text-slate-400 bg-slate-100 dark:bg-slate-700 px-1.5 py-0.5 rounded"
                >{{ t('JABVOX_CUSTOMIZATION.BUTTONS.INACTIVE') }}</span
              >
            </div>
            <div class="flex items-center gap-2">
              <button
                class="text-slate-400 hover:text-woot-600"
                @click="openButtonEdit(btn)"
              >
                <span class="i-lucide-pencil size-4" />
              </button>
              <button
                class="text-slate-400 hover:text-red-500"
                @click="confirmDeleteButton(btn.id)"
              >
                <span class="i-lucide-trash-2 size-4" />
              </button>
            </div>
          </div>

          <!-- Edit form -->
          <div
            v-if="expandedButtonId === btn.id"
            class="border-t border-slate-100 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 p-4 flex flex-col gap-3"
          >
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >{{ t('JABVOX_CUSTOMIZATION.BUTTONS.NAME_LABEL') }}</label
                >
                <input
                  v-model="editButtonForms[btn.id].name_jabvox"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >{{ t('JABVOX_CUSTOMIZATION.BUTTONS.URL_LABEL') }}</label
                >
                <input
                  v-model="editButtonForms[btn.id].url_jabvox"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>
            </div>
            <div class="flex items-center gap-4">
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >{{ t('JABVOX_CUSTOMIZATION.BUTTONS.COLOR_LABEL') }}</label
                >
                <div class="flex gap-2 flex-wrap">
                  <button
                    v-for="color in BUTTON_COLORS"
                    :key="color"
                    class="size-6 rounded-full border-2 transition-transform hover:scale-110"
                    :style="{
                      backgroundColor: color,
                      borderColor:
                        editButtonForms[btn.id].color_jabvox === color
                          ? color
                          : 'transparent',
                    }"
                    :class="
                      editButtonForms[btn.id].color_jabvox === color
                        ? 'scale-110 shadow-md'
                        : ''
                    "
                    @click="editButtonForms[btn.id].color_jabvox = color"
                  />
                </div>
              </div>
              <label class="flex items-center gap-2 cursor-pointer ml-4">
                <input
                  v-model="editButtonForms[btn.id].active_jabvox"
                  type="checkbox"
                  class="rounded border-slate-300"
                />
                <span class="text-sm text-slate-700 dark:text-slate-300">{{
                  t('JABVOX_CUSTOMIZATION.BUTTONS.ACTIVE_LABEL')
                }}</span>
              </label>
            </div>
            <div class="flex gap-2 justify-end">
              <Button
                variant="ghost"
                size="sm"
                :label="t('JABVOX_CUSTOMIZATION.BUTTONS.CANCEL')"
                @click="expandedButtonId = null"
              />
              <Button
                size="sm"
                :label="t('JABVOX_CUSTOMIZATION.BUTTONS.SAVE')"
                :is-loading="uiFlags.isSaving"
                @click="saveEditButton(btn.id)"
              />
            </div>
          </div>

          <!-- Delete confirm -->
          <div
            v-if="deleteButtonConfirmId === btn.id"
            class="border-t border-red-100 bg-red-50 dark:bg-red-900/20 p-3 flex items-center justify-between gap-3"
          >
            <p class="text-sm text-red-700 dark:text-red-300">
              {{
                t('JABVOX_CUSTOMIZATION.BUTTONS.DELETE_CONFIRM', {
                  name: btn.name_jabvox,
                })
              }}
            </p>
            <div class="flex gap-2">
              <Button
                variant="ghost"
                size="sm"
                :label="t('JABVOX_CUSTOMIZATION.BUTTONS.CANCEL')"
                @click="deleteButtonConfirmId = null"
              />
              <Button
                variant="destructive"
                size="sm"
                :label="t('JABVOX_CUSTOMIZATION.BUTTONS.DELETE')"
                @click="doDeleteButton(btn.id)"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
