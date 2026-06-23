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
import ButtonFormDialog from './ButtonFormDialog.vue';
import ConfirmDeleteDialog from './ConfirmDeleteDialog.vue';
import { useClientPagination } from '../composables/useClientPagination';

const store = useStore();
const { t } = useI18n();

const buttons = useMapGetter('jabvoxCustomization/getButtons');
const uiFlags = useMapGetter('jabvoxCustomization/getUIFlags');

const search = ref('');
const formDialog = ref(null);
const deleteDialog = ref(null);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return buttons.value;
  return buttons.value.filter(
    btn =>
      btn.name_jabvox?.toLowerCase().includes(q) ||
      btn.url_jabvox?.toLowerCase().includes(q)
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
} = useClientPagination(filtered, { pageSize: 9 });

const handleSubmit = async ({ mode, id, values }) => {
  try {
    if (mode === 'edit') {
      await store.dispatch('jabvoxCustomization/updateButton', {
        id,
        ...values,
      });
    } else {
      await store.dispatch('jabvoxCustomization/createButton', values);
    }
    formDialog.value?.close();
    useAlert(t('JABVOX_CUSTOMIZATION.BUTTONS.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};

const askDelete = btn => {
  deleteDialog.value?.open({
    title: t('JABVOX_CUSTOMIZATION.BUTTONS.DELETE'),
    description: t('JABVOX_CUSTOMIZATION.BUTTONS.DELETE_CONFIRM', {
      name: btn.name_jabvox,
    }),
    data: btn.id,
  });
};

const doDelete = async id => {
  try {
    await store.dispatch('jabvoxCustomization/deleteButton', id);
    useAlert(t('JABVOX_CUSTOMIZATION.BUTTONS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_CUSTOMIZATION.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <SectionHeader
      :title="t('JABVOX_CUSTOMIZATION.BUTTONS.TITLE')"
      :description="t('JABVOX_CUSTOMIZATION.BUTTONS.DESCRIPTION')"
    >
      <template #action>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.BUTTONS.NEW')"
          size="sm"
          @click="formDialog?.openCreate()"
        />
      </template>
    </SectionHeader>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetchingButtons"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
      {{ t('JABVOX_CUSTOMIZATION.LOADING') }}
    </div>

    <!-- Empty -->
    <EmptyStateLayout
      v-else-if="!buttons.length"
      :title="t('JABVOX_CUSTOMIZATION.BUTTONS.EMPTY_TITLE')"
      :subtitle="t('JABVOX_CUSTOMIZATION.BUTTONS.EMPTY')"
    >
      <template #actions>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_CUSTOMIZATION.BUTTONS.NEW')"
          size="sm"
          @click="formDialog?.openCreate()"
        />
      </template>
    </EmptyStateLayout>

    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <SearchInput
          v-model="search"
          :placeholder="t('JABVOX_CUSTOMIZATION.BUTTONS.SEARCH_PLACEHOLDER')"
          @update:model-value="reset"
        />
        <span class="text-xs text-n-slate-10">
          {{
            t('JABVOX_CUSTOMIZATION.BUTTONS.COUNT', { count: buttons.length })
          }}
        </span>
      </div>

      <!-- No search results -->
      <div
        v-if="!total"
        class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_CUSTOMIZATION.BUTTONS.NO_RESULTS') }}
      </div>

      <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <div
          v-for="btn in paged"
          :key="btn.id"
          class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 transition-shadow hover:shadow-sm"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="flex items-center gap-2 min-w-0">
              <span
                class="size-3 rounded-full inline-block shrink-0"
                :style="{ backgroundColor: btn.color_jabvox }"
              />
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ btn.name_jabvox }}
              </p>
            </div>
            <Label
              v-if="!btn.active_jabvox"
              :label="t('JABVOX_CUSTOMIZATION.BUTTONS.INACTIVE')"
              color="slate"
              compact
            />
            <Label
              v-else
              :label="t('JABVOX_CUSTOMIZATION.BUTTONS.ACTIVE_BADGE')"
              color="teal"
              compact
            />
          </div>

          <p class="text-xs text-n-slate-11 font-mono truncate">
            {{ btn.url_jabvox }}
          </p>

          <div
            class="flex items-center justify-end gap-1 pt-2 border-t border-n-weak"
          >
            <Button
              icon="i-lucide-pencil"
              variant="ghost"
              color="slate"
              size="sm"
              @click="formDialog?.openEdit(btn)"
            />
            <Button
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              @click="askDelete(btn)"
            />
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
        :page-size-options="[6, 9, 12, 24]"
        @prev="goPrev"
        @next="goNext"
      />
    </template>

    <ButtonFormDialog
      ref="formDialog"
      :is-saving="uiFlags.isSaving"
      @submit="handleSubmit"
    />
    <ConfirmDeleteDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
