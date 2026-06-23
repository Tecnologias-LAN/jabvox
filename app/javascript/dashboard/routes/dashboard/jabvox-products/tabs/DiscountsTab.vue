<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SearchInput from '../components/SearchInput.vue';
import ConfirmDialog from '../components/ConfirmDialog.vue';

const store = useStore();
const { t } = useI18n();

const discounts = useMapGetter('jabvoxProducts/getDiscounts');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const search = ref('');
const formDialog = ref(null);
const deleteDialog = ref(null);
const editingItem = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  description_jabvox: '',
  percentage_jabvox: '',
  active_jabvox: true,
});
const form = ref(emptyForm());

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return discounts.value;
  return discounts.value.filter(d => d.name_jabvox?.toLowerCase().includes(q));
});

onMounted(() => store.dispatch('jabvoxProducts/fetchDiscount'));

const openNew = () => {
  editingItem.value = null;
  form.value = emptyForm();
  formDialog.value?.open();
};

const openEdit = item => {
  editingItem.value = item;
  form.value = {
    name_jabvox: item.name_jabvox,
    description_jabvox: item.description_jabvox || '',
    percentage_jabvox: item.percentage_jabvox || '',
    active_jabvox: item.active_jabvox,
  };
  formDialog.value?.open();
};

const onSubmit = async () => {
  if (!form.value.name_jabvox.trim()) return;
  try {
    if (editingItem.value) {
      await store.dispatch('jabvoxProducts/updateDiscount', {
        id: editingItem.value.id,
        ...form.value,
      });
    } else {
      await store.dispatch('jabvoxProducts/createDiscount', form.value);
    }
    formDialog.value?.close();
    useAlert(t('JABVOX_PRODUCTS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const askDelete = item => {
  deleteDialog.value?.open({
    title: t('JABVOX_PRODUCTS.DISCOUNTS.DELETE_TITLE'),
    description: t('JABVOX_PRODUCTS.DISCOUNTS.DELETE_BODY', {
      name: item.name_jabvox,
    }),
    data: item.id,
  });
};
const doDelete = async id => {
  try {
    await store.dispatch('jabvoxProducts/destroyDiscount', id);
    useAlert(t('JABVOX_PRODUCTS.DELETE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <div
      v-if="uiFlags.isFetchingDiscounts"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <EmptyStateLayout
      v-else-if="!discounts.length"
      :title="t('JABVOX_PRODUCTS.DISCOUNTS.EMPTY_TITLE')"
      :subtitle="t('JABVOX_PRODUCTS.DISCOUNTS.EMPTY')"
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
          :placeholder="t('JABVOX_PRODUCTS.DISCOUNTS.SEARCH_PLACEHOLDER')"
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
        {{ t('JABVOX_PRODUCTS.DISCOUNTS.NO_RESULTS') }}
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
            class="i-lucide-tag size-5 text-n-slate-10 shrink-0 hidden sm:block"
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ item.name_jabvox }}
            </p>
            <p
              v-if="item.description_jabvox"
              class="text-xs text-n-slate-10 truncate"
            >
              {{ item.description_jabvox }}
            </p>
          </div>
          <code
            class="font-mono text-sm font-semibold text-n-brand bg-n-alpha-2 rounded-md px-2 py-0.5 shrink-0"
          >
            {{ item.percentage_jabvox }}%
          </code>
          <Label
            :label="
              item.active_jabvox
                ? t('JABVOX_PRODUCTS.ACTIVE')
                : t('JABVOX_PRODUCTS.INACTIVE')
            "
            :color="item.active_jabvox ? 'teal' : 'slate'"
            compact
          />
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
      :disable-confirm-button="!form.name_jabvox.trim()"
      :is-loading="uiFlags.isSavingDiscount"
      width="lg"
      @confirm="onSubmit"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.name_jabvox"
          :label="`${t('JABVOX_PRODUCTS.COLS.NAME')} *`"
          autofocus
        />
        <Input
          v-model="form.percentage_jabvox"
          type="number"
          step="0.01"
          min="0"
          max="100"
          :label="t('JABVOX_PRODUCTS.DISCOUNTS.COLS.PERCENTAGE')"
        />
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_PRODUCTS.COLS.DESCRIPTION') }}
          </label>
          <textarea
            v-model="form.description_jabvox"
            rows="2"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand resize-y"
          />
        </div>
        <div
          class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_PRODUCTS.ACTIVE') }}
          </span>
          <Switch v-model="form.active_jabvox" />
        </div>
      </div>
    </Dialog>

    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
