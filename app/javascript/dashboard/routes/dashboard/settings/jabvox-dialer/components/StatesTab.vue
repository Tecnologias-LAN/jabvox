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
import SearchInput from './SearchInput.vue';
import StateFormDialog from './StateFormDialog.vue';
import ConfirmDialog from './ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();

const dialerStates = useMapGetter('jabvoxDialer/getDialerStates');
const uiFlags = useMapGetter('jabvoxDialer/getUIFlags');

const search = ref('');
const formDialog = ref(null);
const deleteDialog = ref(null);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return dialerStates.value;
  return dialerStates.value.filter(s => s.name?.toLowerCase().includes(q));
});

const handleSubmit = async ({ mode, id, values }) => {
  try {
    if (mode === 'edit') {
      await store.dispatch('jabvoxDialer/updateDialerState', { id, ...values });
    } else {
      await store.dispatch('jabvoxDialer/createDialerState', values);
    }
    formDialog.value?.close();
    useAlert(t('JABVOX_DIALER.DIALER_STATES.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_DIALER.DIALER_STATES.ERROR'));
  }
};

const askDelete = state => {
  deleteDialog.value?.open({
    title: t('JABVOX_DIALER.DIALER_STATES.DELETE_TITLE'),
    description: t('JABVOX_DIALER.DIALER_STATES.DELETE_BODY', {
      name: state.name,
    }),
    data: state.id,
  });
};

const doDelete = async id => {
  try {
    await store.dispatch('jabvoxDialer/deleteDialerState', id);
    useAlert(t('JABVOX_DIALER.DIALER_STATES.DELETED'));
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  }
};

defineExpose({ openCreate: () => formDialog.value?.openCreate() });
</script>

<template>
  <div class="flex flex-col gap-5">
    <div
      class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
    >
      <p class="text-sm text-n-slate-11 max-w-2xl">
        {{ t('JABVOX_DIALER.DIALER_STATES.DESCRIPTION') }}
      </p>
      <Button
        icon="i-lucide-plus"
        :label="t('JABVOX_DIALER.DIALER_STATES.NEW')"
        size="sm"
        class="shrink-0"
        @click="formDialog?.openCreate()"
      />
    </div>

    <div
      v-if="uiFlags.isFetchingStates"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <EmptyStateLayout
      v-else-if="!dialerStates.length"
      :title="t('JABVOX_DIALER.DIALER_STATES.EMPTY_TITLE')"
      :subtitle="t('JABVOX_DIALER.DIALER_STATES.EMPTY')"
    >
      <template #actions>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_DIALER.DIALER_STATES.NEW')"
          size="sm"
          @click="formDialog?.openCreate()"
        />
      </template>
    </EmptyStateLayout>

    <template v-else>
      <SearchInput
        v-model="search"
        :placeholder="t('JABVOX_DIALER.DIALER_STATES.SEARCH_PLACEHOLDER')"
      />

      <div
        v-if="!filtered.length"
        class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_DIALER.DIALER_STATES.NO_RESULTS') }}
      </div>

      <div v-else class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
        <div
          v-for="s in filtered"
          :key="s.id"
          class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
        >
          <span
            class="size-8 rounded-lg shrink-0 ring-1 ring-inset ring-n-weak"
            :style="{ backgroundColor: s.color }"
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ s.name }}
            </p>
            <Label
              v-if="!s.is_active"
              :label="t('JABVOX_DIALER.DIALER_STATES.INACTIVE')"
              color="slate"
              compact
            />
            <Label
              v-else
              :label="t('JABVOX_DIALER.DIALER_STATES.ACTIVE_BADGE')"
              color="teal"
              compact
            />
          </div>
          <div class="flex items-center gap-1 shrink-0">
            <Button
              icon="i-lucide-pencil"
              variant="ghost"
              color="slate"
              size="sm"
              @click="formDialog?.openEdit(s)"
            />
            <Button
              icon="i-lucide-trash-2"
              variant="ghost"
              color="ruby"
              size="sm"
              @click="askDelete(s)"
            />
          </div>
        </div>
      </div>
    </template>

    <StateFormDialog
      ref="formDialog"
      :is-saving="uiFlags.isSavingState"
      @submit="handleSubmit"
    />
    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
