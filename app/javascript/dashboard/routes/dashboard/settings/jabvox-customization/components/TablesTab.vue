<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SectionHeader from './SectionHeader.vue';
import SearchInput from './SearchInput.vue';
import TablePagination from './TablePagination.vue';
import TableFormDialog from './TableFormDialog.vue';
import ConfirmDeleteDialog from './ConfirmDeleteDialog.vue';
import { useClientPagination } from '../composables/useClientPagination';

const store = useStore();
const { t } = useI18n();

const tables = useMapGetter('jabvoxCustomization/getTables');
const uiFlags = useMapGetter('jabvoxCustomization/getUIFlags');

const search = ref('');
const formDialog = ref(null);
const deleteDialog = ref(null);

const leadsTable = computed(
  () => tables.value.find(tbl => tbl.linked_to_jabvox === 'leads') || null
);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return tables.value;
  return tables.value.filter(
    tbl =>
      tbl.name_jabvox?.toLowerCase().includes(q) ||
      tbl.description_jabvox?.toLowerCase().includes(q)
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

const onSearch = () => reset();

const columnsCount = table =>
  t('JABVOX_CUSTOMIZATION.TABLES.COLUMNS_COUNT', {
    count: (table.columns || []).length,
  });

const handleSubmit = async ({ mode, id, values }) => {
  try {
    if (mode === 'edit') {
      await store.dispatch('jabvoxCustomization/updateTable', {
        id,
        ...values,
      });
    } else {
      await store.dispatch('jabvoxCustomization/createTable', values);
    }
    formDialog.value?.close();
    useAlert(t('JABVOX_CUSTOMIZATION.TABLES.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const toggleLeadsLink = async table => {
  const isLinked = table.linked_to_jabvox === 'leads';
  if (!isLinked && leadsTable.value && leadsTable.value.id !== table.id) {
    useAlert(t('JABVOX_CUSTOMIZATION.TABLES.LEADS_LINK_CONFLICT'));
    return;
  }
  try {
    await store.dispatch('jabvoxCustomization/updateTable', {
      id: table.id,
      linked_to_jabvox: isLinked ? null : 'leads',
    });
    useAlert(t('JABVOX_CUSTOMIZATION.TABLES.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const askDelete = table => {
  deleteDialog.value?.open({
    title: t('JABVOX_CUSTOMIZATION.TABLES.DELETE'),
    description: t('JABVOX_CUSTOMIZATION.TABLES.DELETE_CONFIRM', {
      name: table.name_jabvox,
    }),
    data: table.id,
  });
};

const doDelete = async id => {
  try {
    await store.dispatch('jabvoxCustomization/deleteTable', id);
    useAlert(t('JABVOX_CUSTOMIZATION.TABLES.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <SectionHeader
      :title="t('JABVOX_CUSTOMIZATION.TABLES.TITLE')"
      :description="t('JABVOX_CUSTOMIZATION.TABLES.DESCRIPTION')"
    >
      <template #action>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.TABLES.NEW')"
          size="sm"
          @click="formDialog?.openCreate()"
        />
      </template>
    </SectionHeader>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetchingTables"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
      {{ t('JABVOX_CUSTOMIZATION.LOADING') }}
    </div>

    <!-- Empty -->
    <EmptyStateLayout
      v-else-if="!tables.length"
      :title="t('JABVOX_CUSTOMIZATION.TABLES.EMPTY_TITLE')"
      :subtitle="t('JABVOX_CUSTOMIZATION.TABLES.EMPTY')"
    >
      <template #actions>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.TABLES.NEW')"
          size="sm"
          @click="formDialog?.openCreate()"
        />
      </template>
    </EmptyStateLayout>

    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <SearchInput
          v-model="search"
          :placeholder="t('JABVOX_CUSTOMIZATION.TABLES.SEARCH_PLACEHOLDER')"
          @update:model-value="onSearch"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('JABVOX_CUSTOMIZATION.TABLES.COUNT', { count: tables.length }) }}
        </span>
      </div>

      <!-- No search results -->
      <div
        v-if="!total"
        class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_CUSTOMIZATION.TABLES.NO_RESULTS') }}
      </div>

      <!-- Cards grid -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <div
          v-for="table in paged"
          :key="table.id"
          class="group flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 transition-shadow hover:shadow-sm"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="flex items-center gap-2 min-w-0">
              <span class="i-lucide-table size-4 text-n-slate-10 shrink-0" />
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ table.name_jabvox }}
              </p>
            </div>
            <Label
              v-if="table.linked_to_jabvox === 'leads'"
              :label="t('JABVOX_CUSTOMIZATION.COLUMNS.LEADS_HINT')"
              color="iris"
              compact
            />
            <Label
              v-else-if="table.system"
              :label="t('JABVOX_CUSTOMIZATION.TABLES.SYSTEM')"
              color="slate"
              compact
            />
          </div>

          <p
            v-if="table.description_jabvox"
            class="text-xs text-n-slate-11 line-clamp-2 min-h-[2rem]"
          >
            {{ table.description_jabvox }}
          </p>
          <p v-else class="text-xs text-n-slate-10 italic min-h-[2rem]">
            {{ t('JABVOX_CUSTOMIZATION.TABLES.NO_DESCRIPTION') }}
          </p>

          <div
            class="flex items-center justify-between pt-2 border-t border-n-weak"
          >
            <span class="text-xs text-n-slate-10">{{
              columnsCount(table)
            }}</span>
            <!-- System table is read-only -->
            <div
              v-if="table.system"
              class="flex items-center gap-1 text-xs text-n-slate-10"
            >
              <span class="i-lucide-lock size-3.5" />
              {{ t('JABVOX_CUSTOMIZATION.TABLES.SYSTEM') }}
            </div>
            <div v-else class="flex items-center gap-1">
              <Button
                :icon="
                  table.linked_to_jabvox === 'leads'
                    ? 'i-lucide-user-check'
                    : 'i-lucide-user'
                "
                variant="ghost"
                :color="table.linked_to_jabvox === 'leads' ? 'blue' : 'slate'"
                size="sm"
                :title="
                  table.linked_to_jabvox === 'leads'
                    ? t('JABVOX_CUSTOMIZATION.TABLES.UNLINK_LEADS')
                    : t('JABVOX_CUSTOMIZATION.TABLES.LINK_LEADS')
                "
                @click="toggleLeadsLink(table)"
              />
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                @click="formDialog?.openEdit(table)"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="askDelete(table)"
              />
            </div>
          </div>
        </div>
      </div>

      <TablePagination
        v-if="total"
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

    <TableFormDialog
      ref="formDialog"
      :is-saving="uiFlags.isSaving"
      @submit="handleSubmit"
    />
    <ConfirmDeleteDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
