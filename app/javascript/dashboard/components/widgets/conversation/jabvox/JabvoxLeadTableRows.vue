<script setup>
// Shared panel that shows a lead's MULTI-row custom tables (Asesorías, Casos…)
// across Leads / Kanban / Conversations / Dialer. Each table lists its rows;
// rows can be added, edited and removed. Data belongs to the open lead, so it
// is fetched per-lead and kept local (not in global store state).
//
// Supports conditional questions: a column with `depends_on_jabvox` +
// `show_when_jabvox` only appears when the controlling answer in the SAME draft
// matches one of the trigger values. Hidden columns are neither shown nor sent.
// Column types: text, textarea, integer, float, boolean, date, select,
// multiselect (checkbox group, stored as an array).
import { ref, watch, reactive } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

// Se pasa `contactId` (ficha unificada del contacto) o `leadId` (pantallas de lead, que
// desaparecerán). Las filas son las mismas y viven en las mismas tablas; solo cambia de qué
// registro cuelgan, así que basta con elegir el juego de acciones del store.
const props = defineProps({
  leadId: { type: [Number, String], default: null },
  contactId: { type: [Number, String], default: null },
});

const store = useStore();
const { t } = useI18n();

const byContact = () => props.contactId != null && props.contactId !== '';
const ownerId = () => Number(byContact() ? props.contactId : props.leadId);
// Nombre de la acción y clave del id, según de quién cuelguen las filas.
const rowAction = verb =>
  `jabvoxCustomization/${verb}${byContact() ? 'Contact' : 'Lead'}TableRow`;
const ownerKey = () => (byContact() ? 'contactId' : 'leadId');

const tables = ref([]); // [{ table_id, table_name, columns, rows: [{row_id,data}] }]
const loading = ref(false);
const saving = ref(false);
// Draft being added/edited per table: { [tableId]: { rowId|null, data:{} } }
const editing = ref({});
// Which tables are expanded in the panel (collapsed by default keeps it tidy).
const expanded = reactive({});

const isMulti = col => col.column_type_jabvox === 'multiselect';

const emptyDraft = table => {
  const data = {};
  table.columns.forEach(c => {
    if (c.column_type_jabvox === 'boolean') data[c.name_jabvox] = false;
    else if (isMulti(c)) data[c.name_jabvox] = [];
    else data[c.name_jabvox] = '';
  });
  return { rowId: null, data };
};

// A column is visible when it has no dependency, or the controlling answer in
// this same draft/row matches any configured trigger value. Mirrors the
// server-side JabvoxCustomColumn#visible_for? so UI and validation agree.
const isVisible = (col, data) => {
  const dep = col.depends_on_jabvox;
  if (!dep) return true;
  const triggers = (col.show_when_jabvox || []).map(String);
  if (!triggers.length) return true;
  const given = data?.[dep];
  const values = Array.isArray(given)
    ? given.map(String)
    : [String(given ?? '')];
  return values.some(v => triggers.includes(v));
};

const visibleColumns = (table, data) =>
  table.columns.filter(col => isVisible(col, data));

const load = async () => {
  if (!ownerId()) return;
  loading.value = true;
  try {
    const data = await store.dispatch(
      `jabvoxCustomization/fetch${byContact() ? 'Contact' : 'Lead'}TableRows`,
      ownerId()
    );
    tables.value = Array.isArray(data) ? data : [];
  } catch {
    tables.value = [];
  } finally {
    loading.value = false;
  }
};

watch(() => [props.leadId, props.contactId], load, { immediate: true });

const toggle = tableId => {
  expanded[tableId] = !expanded[tableId];
};

const startAdd = table => {
  expanded[table.table_id] = true;
  editing.value = { ...editing.value, [table.table_id]: emptyDraft(table) };
};

const startEdit = (table, row) => {
  expanded[table.table_id] = true;
  // Normalize stored values into editable shapes (multiselect -> array).
  const data = {};
  table.columns.forEach(c => {
    const v = row.data[c.name_jabvox];
    if (isMulti(c)) data[c.name_jabvox] = Array.isArray(v) ? [...v] : [];
    else if (c.column_type_jabvox === 'boolean') data[c.name_jabvox] = !!v;
    else data[c.name_jabvox] = v ?? '';
  });
  editing.value = {
    ...editing.value,
    [table.table_id]: { rowId: row.row_id, data },
  };
};

const cancelEdit = tableId => {
  const next = { ...editing.value };
  delete next[tableId];
  editing.value = next;
};

const inputType = colType =>
  ({ integer: 'number', float: 'number', date: 'date' })[colType] || 'text';

// Toggle a value inside a multiselect array in the draft.
const toggleMulti = (tableId, colName, option) => {
  const arr = editing.value[tableId].data[colName] || [];
  editing.value[tableId].data[colName] = arr.includes(option)
    ? arr.filter(o => o !== option)
    : [...arr, option];
};

// Before saving, drop answers for columns hidden by their condition so no stale
// data from an untaken path is persisted (server also enforces this).
const prunedData = table => {
  const draft = editing.value[table.table_id];
  const visible = new Set(
    visibleColumns(table, draft.data).map(c => c.name_jabvox)
  );
  const out = {};
  Object.keys(draft.data).forEach(k => {
    if (visible.has(k)) out[k] = draft.data[k];
  });
  return out;
};

const saveRow = async table => {
  const draft = editing.value[table.table_id];
  if (!draft) return;
  saving.value = true;
  try {
    const rowData = prunedData(table);
    if (draft.rowId) {
      await store.dispatch(rowAction('update'), {
        [ownerKey()]: ownerId(),
        tableId: table.table_id,
        rowId: draft.rowId,
        rowData,
      });
    } else {
      await store.dispatch(rowAction('create'), {
        [ownerKey()]: ownerId(),
        tableId: table.table_id,
        rowData,
      });
    }
    cancelEdit(table.table_id);
    await load();
    useAlert(t('JABVOX_CUSTOMIZATION.LEAD_ROWS.SAVED'));
  } catch (error) {
    const msg = error?.response?.data?.errors?.join?.(', ');
    useAlert(msg || t('JABVOX_CUSTOMIZATION.LEAD_ROWS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

const deleteRow = async (table, row) => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('JABVOX_CUSTOMIZATION.LEAD_ROWS.DELETE_CONFIRM')))
    return;
  try {
    await store.dispatch(rowAction('delete'), {
      [ownerKey()]: ownerId(),
      tableId: table.table_id,
      rowId: row.row_id,
    });
    await load();
    useAlert(t('JABVOX_CUSTOMIZATION.LEAD_ROWS.DELETED'));
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.LEAD_ROWS.SAVE_ERROR'));
  }
};

// Human-readable cell for the row summary list.
const cellValue = (col, value) => {
  if (col.column_type_jabvox === 'boolean') {
    return value
      ? t('JABVOX_CUSTOMIZATION.LEAD_ROWS.YES')
      : t('JABVOX_CUSTOMIZATION.LEAD_ROWS.NO');
  }
  if (Array.isArray(value)) return value.length ? value.join(', ') : '—';
  return value === '' || value == null ? '—' : value;
};
</script>

<template>
  <div class="flex flex-col gap-4 p-4">
    <div v-if="loading" class="text-sm text-n-slate-10 py-6 text-center">
      {{ t('JABVOX_CUSTOMIZATION.LOADING') }}
    </div>

    <div
      v-else-if="!tables.length"
      class="text-sm text-n-slate-10 py-6 text-center border border-dashed border-n-weak rounded-xl"
    >
      {{ t('JABVOX_CUSTOMIZATION.LEAD_ROWS.EMPTY_TEXT') }}
    </div>

    <div
      v-for="table in tables"
      :key="table.table_id"
      class="rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden"
    >
      <!-- Section header: click to expand/collapse -->
      <div
        class="flex items-center justify-between px-4 py-3 bg-n-alpha-1 border-b border-n-weak"
      >
        <button
          type="button"
          class="flex items-center gap-2 min-w-0 flex-1 text-left"
          @click="toggle(table.table_id)"
        >
          <span
            class="size-4 shrink-0 text-n-slate-10 transition-transform"
            :class="
              expanded[table.table_id]
                ? 'i-lucide-chevron-down'
                : 'i-lucide-chevron-right'
            "
          />
          <span class="min-w-0">
            <span class="block text-sm font-semibold text-n-slate-12 truncate">
              {{ table.table_name }}
              <span class="font-normal text-n-slate-10"
                >({{ (table.rows || []).length }})</span
              >
            </span>
            <span
              v-if="table.table_description"
              class="block text-xs text-n-slate-10 truncate"
            >
              {{ table.table_description }}
            </span>
          </span>
        </button>
        <Button
          v-if="!editing[table.table_id]"
          size="sm"
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.LEAD_ROWS.ADD')"
          @click="startAdd(table)"
        />
      </div>

      <div v-show="expanded[table.table_id]">
        <!-- Existing rows -->
        <div class="divide-y divide-n-weak">
          <div
            v-for="row in table.rows"
            :key="row.row_id"
            class="flex items-start justify-between gap-3 px-4 py-2.5"
          >
            <div class="min-w-0 flex flex-col gap-0.5">
              <p
                v-for="col in visibleColumns(table, row.data)"
                :key="col.id"
                class="text-xs text-n-slate-11 break-words"
              >
                <span class="text-n-slate-10">{{ col.label_jabvox }}:</span>
                {{ cellValue(col, row.data[col.name_jabvox]) }}
              </p>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <button
                type="button"
                class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                @click="startEdit(table, row)"
              >
                <span class="i-lucide-pencil size-4" />
              </button>
              <button
                type="button"
                class="p-1 rounded text-n-ruby-11 hover:bg-n-alpha-2"
                @click="deleteRow(table, row)"
              >
                <span class="i-lucide-trash-2 size-4" />
              </button>
            </div>
          </div>
          <p
            v-if="!table.rows.length && !editing[table.table_id]"
            class="px-4 py-3 text-xs text-n-slate-10"
          >
            {{ t('JABVOX_CUSTOMIZATION.LEAD_ROWS.NO_RECORDS') }}
          </p>
        </div>

        <!-- Add / edit form -->
        <div
          v-if="editing[table.table_id]"
          class="border-t border-n-weak p-4 grid grid-cols-2 gap-x-4 gap-y-3 bg-n-alpha-1"
        >
          <template
            v-for="col in visibleColumns(table, editing[table.table_id].data)"
            :key="col.id"
          >
            <!-- Boolean -->
            <div
              v-if="col.column_type_jabvox === 'boolean'"
              class="col-span-2 flex items-center gap-2"
            >
              <input
                :id="`ed-${table.table_id}-${col.id}`"
                v-model="editing[table.table_id].data[col.name_jabvox]"
                type="checkbox"
                class="rounded accent-n-brand"
              />
              <label
                :for="`ed-${table.table_id}-${col.id}`"
                class="text-sm text-n-slate-12 cursor-pointer"
              >
                {{ col.label_jabvox }}
              </label>
            </div>

            <!-- Textarea (long text) -->
            <div
              v-else-if="col.column_type_jabvox === 'textarea'"
              class="col-span-2 flex flex-col gap-1"
            >
              <label class="text-xs text-n-slate-11">{{
                col.label_jabvox
              }}</label>
              <textarea
                v-model="editing[table.table_id].data[col.name_jabvox]"
                rows="3"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 resize-y"
              />
            </div>

            <!-- Single select -->
            <div
              v-else-if="col.column_type_jabvox === 'select'"
              class="col-span-1 flex flex-col gap-1"
            >
              <label class="text-xs text-n-slate-11">{{
                col.label_jabvox
              }}</label>
              <select
                v-model="editing[table.table_id].data[col.name_jabvox]"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5"
              >
                <option value="">
                  {{ t('JABVOX_CUSTOMIZATION.LEAD_ROWS.SELECT_EMPTY') }}
                </option>
                <option
                  v-for="opt in col.options_jabvox || []"
                  :key="opt"
                  :value="opt"
                >
                  {{ opt }}
                </option>
              </select>
            </div>

            <!-- Multiselect (checkbox group) -->
            <div
              v-else-if="col.column_type_jabvox === 'multiselect'"
              class="col-span-2 flex flex-col gap-1.5"
            >
              <label class="text-xs text-n-slate-11">{{
                col.label_jabvox
              }}</label>
              <div class="flex flex-wrap gap-x-4 gap-y-1.5">
                <label
                  v-for="opt in col.options_jabvox || []"
                  :key="opt"
                  class="flex items-center gap-1.5 text-sm text-n-slate-12 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    class="rounded accent-n-brand"
                    :checked="
                      (
                        editing[table.table_id].data[col.name_jabvox] || []
                      ).includes(opt)
                    "
                    @change="toggleMulti(table.table_id, col.name_jabvox, opt)"
                  />
                  {{ opt }}
                </label>
              </div>
            </div>

            <!-- Text / integer / float / date -->
            <div v-else class="col-span-1 flex flex-col gap-1">
              <label class="text-xs text-n-slate-11">{{
                col.label_jabvox
              }}</label>
              <input
                v-model="editing[table.table_id].data[col.name_jabvox]"
                :type="inputType(col.column_type_jabvox)"
                :step="col.column_type_jabvox === 'float' ? '0.01' : undefined"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5"
              />
            </div>
          </template>

          <div class="col-span-2 flex justify-end gap-2">
            <Button
              variant="ghost"
              size="sm"
              :label="t('JABVOX_CUSTOMIZATION.LEAD_ROWS.CANCEL')"
              @click="cancelEdit(table.table_id)"
            />
            <Button
              size="sm"
              :label="t('JABVOX_CUSTOMIZATION.LEAD_ROWS.SAVE')"
              :is-loading="saving"
              @click="saveRow(table)"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
