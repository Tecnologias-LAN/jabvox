<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Select from 'dashboard/components-next/select/Select.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SectionHeader from './SectionHeader.vue';
import ConfirmDeleteDialog from './ConfirmDeleteDialog.vue';
import RowFormDialog from './RowFormDialog.vue';

const store = useStore();
const { t } = useI18n();

const tables = useMapGetter('jabvoxCustomization/getTables');
const uiFlags = useMapGetter('jabvoxCustomization/getUIFlags');

const selectedTableId = ref(null);
const columns = ref([]);
const rows = ref([]);
const loading = ref(false);
const formDialog = ref(null);
const deleteDialog = ref(null);

// Only standalone tables have their own free-standing records. Lead-linked
// tables (and the system Leads table) are filled from the lead detail, so we
// keep them out of this data editor.
const standaloneTables = computed(() =>
  tables.value.filter(tbl => !tbl.linked_to_jabvox)
);

const tableOptions = computed(() =>
  standaloneTables.value.map(tbl => ({ value: tbl.id, label: tbl.name_jabvox }))
);

const loadData = async tableId => {
  if (!tableId) {
    columns.value = [];
    rows.value = [];
    return;
  }
  loading.value = true;
  try {
    const data = await store.dispatch(
      'jabvoxCustomization/fetchTableData',
      tableId
    );
    columns.value = data.table?.columns || [];
    rows.value = data.rows || [];
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  } finally {
    loading.value = false;
  }
};

watch(selectedTableId, id => loadData(id));

// Renders a stored value for display in the table cell.
const displayValue = (row, column) => {
  const value = row.data?.[column.name_jabvox];
  if (value === null || value === undefined || value === '') return '—';
  if (column.column_type_jabvox === 'boolean') {
    return value
      ? t('JABVOX_CUSTOMIZATION.DATA.YES')
      : t('JABVOX_CUSTOMIZATION.DATA.NO');
  }
  return String(value);
};

const openCreate = () => {
  formDialog.value?.open({ columns: columns.value, row: null });
};

const openEdit = row => {
  formDialog.value?.open({ columns: columns.value, row });
};

const handleSubmit = async ({ rowId, values }) => {
  try {
    if (rowId) {
      await store.dispatch('jabvoxCustomization/updateRow', {
        tableId: selectedTableId.value,
        rowId,
        rowData: values,
      });
    } else {
      await store.dispatch('jabvoxCustomization/createRow', {
        tableId: selectedTableId.value,
        rowData: values,
      });
    }
    formDialog.value?.close();
    useAlert(t('JABVOX_CUSTOMIZATION.DATA.SAVE_SUCCESS'));
    await loadData(selectedTableId.value);
  } catch (error) {
    const messages = error?.response?.data?.errors;
    useAlert(
      Array.isArray(messages) && messages.length
        ? messages.join(' · ')
        : t('JABVOX_CUSTOMIZATION.ERROR')
    );
  }
};

const askDelete = row => {
  deleteDialog.value?.open({
    title: t('JABVOX_CUSTOMIZATION.DATA.DELETE'),
    description: t('JABVOX_CUSTOMIZATION.DATA.DELETE_CONFIRM'),
    data: row.id,
  });
};

const doDelete = async rowId => {
  try {
    await store.dispatch('jabvoxCustomization/deleteRow', {
      tableId: selectedTableId.value,
      rowId,
    });
    useAlert(t('JABVOX_CUSTOMIZATION.DATA.DELETE_SUCCESS'));
    await loadData(selectedTableId.value);
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <SectionHeader
      :title="t('JABVOX_CUSTOMIZATION.DATA.TITLE')"
      :description="t('JABVOX_CUSTOMIZATION.DATA.SUBTITLE')"
    />

    <div class="flex flex-col sm:flex-row sm:items-end gap-3">
      <div class="w-full sm:w-72">
        <Select
          v-model="selectedTableId"
          :options="tableOptions"
          :placeholder="t('JABVOX_CUSTOMIZATION.DATA.SELECT_TABLE')"
        />
      </div>
      <button
        v-if="selectedTableId && columns.length"
        type="button"
        class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white hover:opacity-90 transition-opacity"
        @click="openCreate"
      >
        <span class="i-lucide-plus size-4" aria-hidden="true" />
        {{ t('JABVOX_CUSTOMIZATION.DATA.ADD_ROW') }}
      </button>
    </div>

    <!-- No table selected -->
    <EmptyStateLayout
      v-if="!selectedTableId"
      :title="t('JABVOX_CUSTOMIZATION.DATA.EMPTY_NO_TABLE')"
      :subtitle="t('JABVOX_CUSTOMIZATION.DATA.EMPTY_NO_TABLE_SUB')"
    />

    <!-- Selected table has no columns yet -->
    <EmptyStateLayout
      v-else-if="!loading && !columns.length"
      :title="t('JABVOX_CUSTOMIZATION.DATA.EMPTY_NO_COLUMNS')"
      :subtitle="t('JABVOX_CUSTOMIZATION.DATA.EMPTY_NO_COLUMNS_SUB')"
    />

    <p v-else-if="loading" class="text-sm text-n-slate-11 py-6">
      {{ t('JABVOX_CUSTOMIZATION.DATA.LOADING') }}
    </p>

    <template v-else>
      <p v-if="!rows.length" class="text-sm text-n-slate-11 py-6 text-center">
        {{ t('JABVOX_CUSTOMIZATION.DATA.EMPTY_ROWS') }}
      </p>

      <div v-else class="overflow-x-auto border rounded-lg border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11">
            <tr>
              <th
                v-for="column in columns"
                :key="column.id"
                class="px-3 py-2 text-left whitespace-nowrap font-medium"
              >
                {{ column.label_jabvox }}
              </th>
              <th class="px-3 py-2 w-24" aria-hidden="true" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="row.id"
              class="border-t border-n-weak hover:bg-n-alpha-1"
            >
              <td
                v-for="column in columns"
                :key="column.id"
                class="px-3 py-2 text-n-slate-12 whitespace-nowrap"
              >
                {{ displayValue(row, column) }}
              </td>
              <td class="px-3 py-2">
                <div class="flex items-center justify-end gap-1">
                  <button
                    type="button"
                    class="p-1.5 rounded text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
                    :title="t('JABVOX_CUSTOMIZATION.DATA.EDIT')"
                    @click="openEdit(row)"
                  >
                    <span class="i-lucide-pencil size-4" aria-hidden="true" />
                  </button>
                  <button
                    type="button"
                    class="p-1.5 rounded text-n-ruby-11 hover:bg-n-alpha-2"
                    :title="t('JABVOX_CUSTOMIZATION.DATA.DELETE')"
                    @click="askDelete(row)"
                  >
                    <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <RowFormDialog
      ref="formDialog"
      :saving="uiFlags.isSaving"
      @submit="handleSubmit"
    />
    <ConfirmDeleteDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
