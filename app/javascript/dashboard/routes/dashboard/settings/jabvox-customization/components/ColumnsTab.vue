<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SectionHeader from './SectionHeader.vue';
import SearchInput from './SearchInput.vue';
import TablePagination from './TablePagination.vue';
import ColumnFormDialog from './ColumnFormDialog.vue';
import ConfirmDeleteDialog from './ConfirmDeleteDialog.vue';
import { useClientPagination } from '../composables/useClientPagination';

const store = useStore();
const { t } = useI18n();

const tables = useMapGetter('jabvoxCustomization/getTables');
const uiFlags = useMapGetter('jabvoxCustomization/getUIFlags');

const selectedTableId = ref(null);
const search = ref('');
const formDialog = ref(null);
const deleteDialog = ref(null);

// Leads table first, then the rest.
const sortedTables = computed(() => {
  const leads = tables.value.filter(tbl => tbl.linked_to_jabvox === 'contacts');
  const rest = tables.value.filter(tbl => tbl.linked_to_jabvox !== 'contacts');
  return [...leads, ...rest];
});

const tableOptions = computed(() =>
  sortedTables.value.map(tbl => ({
    value: tbl.id,
    label:
      tbl.linked_to_jabvox === 'contacts'
        ? t('JABVOX_CUSTOMIZATION.COLUMNS.LEADS_OPTION')
        : tbl.name_jabvox,
  }))
);

const selectedTable = computed(() =>
  tables.value.find(tbl => tbl.id === selectedTableId.value)
);
const isLeads = computed(
  () => selectedTable.value?.linked_to_jabvox === 'contacts'
);
const columns = computed(() => selectedTable.value?.columns || []);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return columns.value;
  return columns.value.filter(
    col =>
      col.name_jabvox?.toLowerCase().includes(q) ||
      col.label_jabvox?.toLowerCase().includes(q)
  );
});

const {
  page,
  pageSize,
  total,
  totalPages,
  paged,
  rangeStart,
  rangeEnd,
  goPrev,
  goNext,
  reset,
} = useClientPagination(filtered, { pageSize: 10 });

// Reset pagination/search when the table selection changes.
watch(selectedTableId, () => {
  search.value = '';
  reset();
});

const typeLabel = type => t(`JABVOX_CUSTOMIZATION.COLUMNS.TYPES.${type}`);

const handleSubmit = async ({ mode, id, values }) => {
  if (!selectedTableId.value) return;
  try {
    if (mode === 'edit') {
      await store.dispatch('jabvoxCustomization/updateColumn', {
        tableId: selectedTableId.value,
        id,
        ...values,
      });
    } else {
      await store.dispatch('jabvoxCustomization/createColumn', {
        tableId: selectedTableId.value,
        ...values,
      });
    }
    formDialog.value?.close();
    useAlert(t('JABVOX_CUSTOMIZATION.COLUMNS.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const askDelete = col => {
  deleteDialog.value?.open({
    title: t('JABVOX_CUSTOMIZATION.COLUMNS.DELETE'),
    description: t('JABVOX_CUSTOMIZATION.COLUMNS.DELETE_CONFIRM', {
      name: col.label_jabvox,
    }),
    data: col.id,
  });
};

const doDelete = async id => {
  try {
    await store.dispatch('jabvoxCustomization/deleteColumn', {
      tableId: selectedTableId.value,
      id,
    });
    useAlert(t('JABVOX_CUSTOMIZATION.COLUMNS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <SectionHeader
      :title="t('JABVOX_CUSTOMIZATION.COLUMNS.TITLE')"
      :description="t('JABVOX_CUSTOMIZATION.COLUMNS.DESCRIPTION')"
    />

    <!-- Table selector -->
    <div class="flex flex-col gap-1.5 max-w-sm">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_CUSTOMIZATION.COLUMNS.SELECT_TABLE') }}
      </span>
      <Select
        v-model="selectedTableId"
        :options="tableOptions"
        :placeholder="
          t('JABVOX_CUSTOMIZATION.COLUMNS.SELECT_TABLE_PLACEHOLDER')
        "
      />
    </div>

    <!-- No table selected -->
    <EmptyStateLayout
      v-if="!selectedTableId"
      :title="t('JABVOX_CUSTOMIZATION.COLUMNS.NO_TABLE_TITLE')"
      :subtitle="t('JABVOX_CUSTOMIZATION.COLUMNS.NO_TABLE_SELECTED')"
    />

    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2 min-w-0">
          <p class="text-sm font-medium text-n-slate-12 truncate">
            {{
              isLeads
                ? t('JABVOX_CUSTOMIZATION.COLUMNS.LEADS_OPTION')
                : selectedTable?.name_jabvox
            }}
          </p>
          <Label
            v-if="isLeads"
            :label="t('JABVOX_CUSTOMIZATION.COLUMNS.LEADS_HINT')"
            color="iris"
            compact
          />
        </div>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.COLUMNS.NEW')"
          size="sm"
          @click="formDialog?.openCreate()"
        />
      </div>

      <SearchInput
        v-if="columns.length"
        v-model="search"
        :placeholder="t('JABVOX_CUSTOMIZATION.COLUMNS.SEARCH_PLACEHOLDER')"
        @update:model-value="reset"
      />

      <!-- Empty: no columns at all -->
      <EmptyStateLayout
        v-if="!columns.length"
        :title="t('JABVOX_CUSTOMIZATION.COLUMNS.EMPTY_TITLE')"
        :subtitle="t('JABVOX_CUSTOMIZATION.COLUMNS.EMPTY')"
      >
        <template #actions>
          <Button
            icon="i-lucide-plus"
            :label="t('JABVOX_CUSTOMIZATION.COLUMNS.NEW')"
            size="sm"
            @click="formDialog?.openCreate()"
          />
        </template>
      </EmptyStateLayout>

      <!-- No search results -->
      <div
        v-else-if="!total"
        class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_CUSTOMIZATION.COLUMNS.NO_RESULTS') }}
      </div>

      <template v-else>
        <!-- Modern table (desktop) -->
        <div
          class="hidden sm:block rounded-2xl border border-n-weak overflow-hidden"
        >
          <table class="w-full text-sm">
            <thead
              class="sticky top-0 bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
            >
              <tr>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_CUSTOMIZATION.COLUMNS.DISPLAY_LABEL') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_CUSTOMIZATION.COLUMNS.INTERNAL_NAME_LABEL') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_CUSTOMIZATION.COLUMNS.TYPE_LABEL') }}
                </th>
                <th class="text-center px-4 py-2.5">
                  {{ t('JABVOX_CUSTOMIZATION.COLUMNS.REQUIRED_LABEL') }}
                </th>
                <th class="px-4 py-2.5" />
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="col in paged"
                :key="col.id"
                class="hover:bg-n-alpha-1 transition-colors"
              >
                <td class="px-4 py-3 text-n-slate-12">
                  {{ col.label_jabvox }}
                </td>
                <td class="px-4 py-3">
                  <code
                    class="text-xs px-2 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11 font-mono"
                  >
                    {{ col.name_jabvox }}
                  </code>
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ typeLabel(col.column_type_jabvox) }}
                </td>
                <td class="px-4 py-3 text-center">
                  <Label
                    v-if="col.required_jabvox"
                    :label="t('JABVOX_CUSTOMIZATION.COLUMNS.REQUIRED_BADGE')"
                    color="ruby"
                    compact
                  />
                  <span v-else class="text-n-slate-10">—</span>
                </td>
                <td class="px-4 py-3">
                  <div class="flex items-center justify-end gap-1">
                    <Button
                      icon="i-lucide-pencil"
                      variant="ghost"
                      color="slate"
                      size="sm"
                      @click="formDialog?.openEdit(col)"
                    />
                    <Button
                      icon="i-lucide-trash-2"
                      variant="ghost"
                      color="ruby"
                      size="sm"
                      @click="askDelete(col)"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Cards (mobile) -->
        <div class="sm:hidden flex flex-col gap-3">
          <div
            v-for="col in paged"
            :key="col.id"
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-2"
          >
            <div class="flex items-start justify-between gap-2">
              <p class="text-sm font-medium text-n-slate-12">
                {{ col.label_jabvox }}
              </p>
              <Label
                v-if="col.required_jabvox"
                :label="t('JABVOX_CUSTOMIZATION.COLUMNS.REQUIRED_BADGE')"
                color="ruby"
                compact
              />
            </div>
            <div class="flex items-center gap-2 text-xs">
              <code
                class="px-2 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11 font-mono"
              >
                {{ col.name_jabvox }}
              </code>
              <span class="text-n-slate-10">{{
                typeLabel(col.column_type_jabvox)
              }}</span>
            </div>
            <div class="flex items-center justify-end gap-1 pt-1">
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                @click="formDialog?.openEdit(col)"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="askDelete(col)"
              />
            </div>
          </div>
        </div>

        <TablePagination
          v-model:page-size="pageSize"
          :page="page"
          :total-pages="totalPages"
          :range-start="rangeStart"
          :range-end="rangeEnd"
          :total="total"
          @prev="goPrev"
          @next="goNext"
        />
      </template>
    </template>

    <ColumnFormDialog
      ref="formDialog"
      :is-saving="uiFlags.isSaving"
      :columns="columns"
      @submit="handleSubmit"
    />
    <ConfirmDeleteDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
