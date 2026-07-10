<script setup>
// Shared panel that shows a lead's MULTI-row custom tables (Asesorías, Casos…)
// across Leads / Kanban / Conversations / Dialer. Each table lists its rows;
// rows can be added, edited and removed. Data belongs to the open lead, so it
// is fetched per-lead and kept local (not in global store state).
import { ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  leadId: { type: [Number, String], required: true },
});

const store = useStore();
const { t } = useI18n();

const tables = ref([]); // [{ table_id, table_name, columns, rows: [{row_id,data}] }]
const loading = ref(false);
const saving = ref(false);
// Draft being added/edited per table: { [tableId]: { rowId|null, data:{} } }
const editing = ref({});

const emptyDraft = table => {
  const data = {};
  table.columns.forEach(c => {
    data[c.name_jabvox] = c.column_type_jabvox === 'boolean' ? false : '';
  });
  return { rowId: null, data };
};

const load = async () => {
  if (!props.leadId) return;
  loading.value = true;
  try {
    const data = await store.dispatch(
      'jabvoxCustomization/fetchLeadTableRows',
      Number(props.leadId)
    );
    tables.value = Array.isArray(data) ? data : [];
  } catch {
    tables.value = [];
  } finally {
    loading.value = false;
  }
};

watch(() => props.leadId, load, { immediate: true });

const startAdd = table => {
  editing.value = { ...editing.value, [table.table_id]: emptyDraft(table) };
};

const startEdit = (table, row) => {
  editing.value = {
    ...editing.value,
    [table.table_id]: { rowId: row.row_id, data: { ...row.data } },
  };
};

const cancelEdit = tableId => {
  const next = { ...editing.value };
  delete next[tableId];
  editing.value = next;
};

const inputType = colType =>
  ({ integer: 'number', float: 'number', date: 'date' })[colType] || 'text';

const saveRow = async table => {
  const draft = editing.value[table.table_id];
  if (!draft) return;
  saving.value = true;
  try {
    if (draft.rowId) {
      await store.dispatch('jabvoxCustomization/updateLeadTableRow', {
        leadId: Number(props.leadId),
        tableId: table.table_id,
        rowId: draft.rowId,
        rowData: draft.data,
      });
    } else {
      await store.dispatch('jabvoxCustomization/createLeadTableRow', {
        leadId: Number(props.leadId),
        tableId: table.table_id,
        rowData: draft.data,
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
    await store.dispatch('jabvoxCustomization/deleteLeadTableRow', {
      leadId: Number(props.leadId),
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
      <div
        class="flex items-center justify-between px-4 py-3 bg-n-alpha-1 border-b border-n-weak"
      >
        <div class="min-w-0">
          <p class="text-sm font-semibold text-n-slate-12 truncate">
            {{ table.table_name }}
          </p>
          <p
            v-if="table.table_description"
            class="text-xs text-n-slate-10 truncate"
          >
            {{ table.table_description }}
          </p>
        </div>
        <Button
          v-if="!editing[table.table_id]"
          size="sm"
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.LEAD_ROWS.ADD')"
          @click="startAdd(table)"
        />
      </div>

      <!-- Existing rows -->
      <div class="divide-y divide-n-weak">
        <div
          v-for="row in table.rows"
          :key="row.row_id"
          class="flex items-start justify-between gap-3 px-4 py-2.5"
        >
          <div class="min-w-0 flex flex-col gap-0.5">
            <p
              v-for="col in table.columns"
              :key="col.id"
              class="text-xs text-n-slate-11 truncate"
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
        <div
          v-for="col in table.columns"
          :key="col.id"
          :class="
            col.column_type_jabvox === 'boolean'
              ? 'col-span-2 flex items-center gap-2'
              : 'col-span-1 flex flex-col gap-1'
          "
        >
          <template v-if="col.column_type_jabvox === 'boolean'">
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
          </template>
          <template v-else-if="col.column_type_jabvox === 'select'">
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
          </template>
          <template v-else>
            <label class="text-xs text-n-slate-11">{{
              col.label_jabvox
            }}</label>
            <input
              v-model="editing[table.table_id].data[col.name_jabvox]"
              :type="inputType(col.column_type_jabvox)"
              :step="col.column_type_jabvox === 'float' ? '0.01' : undefined"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5"
            />
          </template>
        </div>
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
</template>
