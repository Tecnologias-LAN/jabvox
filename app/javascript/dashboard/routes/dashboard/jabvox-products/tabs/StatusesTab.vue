<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SearchInput from '../components/SearchInput.vue';
import ConfirmDialog from '../components/ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();

const statuses = useMapGetter('jabvoxProducts/getOrderStatusConfigs');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const search = ref('');
const formDialog = ref(null);
const deleteDialog = ref(null);
const editingItem = ref(null);

const emptyForm = () => ({
  key_jabvox: '',
  label_jabvox: '',
  sort_order_jabvox: 0,
  color_jabvox: '#6B7280',
});
const form = ref(emptyForm());

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return statuses.value;
  return statuses.value.filter(
    s =>
      s.label_jabvox?.toLowerCase().includes(q) ||
      s.key_jabvox?.toLowerCase().includes(q)
  );
});

onMounted(() => store.dispatch('jabvoxProducts/fetchStatus'));

const openNew = () => {
  editingItem.value = null;
  form.value = { ...emptyForm(), sort_order_jabvox: statuses.value.length };
  formDialog.value?.open();
};

const openEdit = item => {
  editingItem.value = item;
  form.value = {
    key_jabvox: item.key_jabvox,
    label_jabvox: item.label_jabvox,
    sort_order_jabvox: item.sort_order_jabvox,
    color_jabvox: item.color_jabvox || '#6B7280',
  };
  formDialog.value?.open();
};

const isValid = computed(
  () => form.value.key_jabvox.trim() && form.value.label_jabvox.trim()
);

const onSubmit = async () => {
  if (!isValid.value) return;
  try {
    if (editingItem.value) {
      await store.dispatch('jabvoxProducts/updateStatus', {
        id: editingItem.value.id,
        ...form.value,
      });
    } else {
      await store.dispatch('jabvoxProducts/createStatus', form.value);
    }
    formDialog.value?.close();
    useAlert(t('JABVOX_PRODUCTS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const askDelete = item => {
  deleteDialog.value?.open({
    title: t('JABVOX_PRODUCTS.STATUSES.DELETE_TITLE'),
    description: t('JABVOX_PRODUCTS.STATUSES.DELETE_BODY', {
      name: item.label_jabvox,
    }),
    data: item.id,
  });
};
const doDelete = async id => {
  try {
    await store.dispatch('jabvoxProducts/destroyStatus', id);
    useAlert(t('JABVOX_PRODUCTS.DELETE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <div
      v-if="uiFlags.isFetchingStatuses"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <EmptyStateLayout
      v-else-if="!statuses.length"
      :title="t('JABVOX_PRODUCTS.STATUSES.EMPTY_TITLE')"
      :subtitle="t('JABVOX_PRODUCTS.STATUSES.EMPTY')"
    >
      <template #actions>
        <Button
          icon="i-lucide-plus"
          :label="t('JABVOX_PRODUCTS.NEW')"
          size="sm"
          @click="openNew"
        />
      </template>
    </EmptyStateLayout>

    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <SearchInput
          v-model="search"
          :placeholder="t('JABVOX_PRODUCTS.STATUSES.SEARCH_PLACEHOLDER')"
        />
        <Button
          :label="t('JABVOX_PRODUCTS.NEW')"
          icon="i-lucide-plus"
          size="sm"
          @click="openNew"
        />
      </div>

      <div
        v-if="!filtered.length"
        class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
      >
        {{ t('JABVOX_PRODUCTS.STATUSES.NO_RESULTS') }}
      </div>

      <div
        v-else
        class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm divide-y divide-n-weak overflow-hidden"
      >
        <div
          v-for="item in filtered"
          :key="item.id"
          class="flex items-center gap-3 px-4 py-3 hover:bg-n-alpha-1 transition-colors"
        >
          <span
            class="size-7 rounded-lg shrink-0 ring-1 ring-inset ring-n-weak"
            :style="{ backgroundColor: item.color_jabvox }"
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ item.label_jabvox }}
            </p>
            <code class="text-xs font-mono text-n-slate-10">
              {{ item.key_jabvox }}
            </code>
          </div>
          <span class="text-xs text-n-slate-10 tabular-nums shrink-0">
            #{{ item.sort_order_jabvox }}
          </span>
          <Button
            icon="i-lucide-pencil"
            variant="ghost"
            color="slate"
            size="sm"
            @click="openEdit(item)"
          />
          <Button
            icon="i-lucide-trash-2"
            variant="ghost"
            color="ruby"
            size="sm"
            @click="askDelete(item)"
          />
        </div>
      </div>
    </template>

    <Dialog
      ref="formDialog"
      :title="
        editingItem ? t('JABVOX_PRODUCTS.EDIT') : t('JABVOX_PRODUCTS.NEW')
      "
      :confirm-button-label="t('JABVOX_PRODUCTS.SAVE')"
      :cancel-button-label="t('JABVOX_PRODUCTS.CANCEL')"
      :disable-confirm-button="!isValid"
      :is-loading="uiFlags.isSavingStatus"
      width="lg"
      @confirm="onSubmit"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.key_jabvox"
          :label="`${t('JABVOX_PRODUCTS.STATUSES.COLS.KEY')} *`"
          :placeholder="t('JABVOX_PRODUCTS.STATUSES.FORM.KEY_PLACEHOLDER')"
          custom-input-class="font-mono"
          autofocus
        />
        <Input
          v-model="form.label_jabvox"
          :label="`${t('JABVOX_PRODUCTS.STATUSES.COLS.LABEL')} *`"
        />
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_PRODUCTS.STATUSES.COLS.COLOR') }}
            </label>
            <div class="flex items-center gap-2">
              <input
                v-model="form.color_jabvox"
                type="color"
                class="w-10 h-9 rounded-lg cursor-pointer border border-n-weak p-0.5 bg-n-solid-1 shrink-0"
              />
              <div class="flex-1">
                <Input
                  v-model="form.color_jabvox"
                  size="sm"
                  custom-input-class="font-mono"
                />
              </div>
            </div>
          </div>
          <Input
            v-model.number="form.sort_order_jabvox"
            type="number"
            min="0"
            :label="t('JABVOX_PRODUCTS.STATUSES.COLS.ORDER')"
          />
        </div>
      </div>
    </Dialog>

    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
