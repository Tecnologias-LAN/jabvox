<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const discounts = useMapGetter('jabvoxProducts/getDiscounts');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const showForm = ref(false);
const editingItem = ref(null);
const form = ref({
  name_jabvox: '',
  description_jabvox: '',
  percentage_jabvox: '',
  active_jabvox: true,
});

onMounted(() => store.dispatch('jabvoxProducts/fetchDiscount'));

const openNew = () => {
  editingItem.value = null;
  form.value = {
    name_jabvox: '',
    description_jabvox: '',
    percentage_jabvox: '',
    active_jabvox: true,
  };
  showForm.value = true;
};

const openEdit = item => {
  editingItem.value = item;
  form.value = {
    name_jabvox: item.name_jabvox,
    description_jabvox: item.description_jabvox || '',
    percentage_jabvox: item.percentage_jabvox,
    active_jabvox: item.active_jabvox,
  };
  showForm.value = true;
};

const onSubmit = async () => {
  if (!form.value.name_jabvox.trim()) {
    useAlert(t('JABVOX_PRODUCTS.DISCOUNTS.FORM.NAME_REQUIRED'));
    return;
  }
  try {
    if (editingItem.value) {
      await store.dispatch('jabvoxProducts/updateDiscount', {
        id: editingItem.value.id,
        ...form.value,
      });
    } else {
      await store.dispatch('jabvoxProducts/createDiscount', form.value);
    }
    useAlert(t('JABVOX_PRODUCTS.SAVE_SUCCESS'));
    showForm.value = false;
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const onDelete = async item => {
  if (
    !window.confirm(
      t('JABVOX_PRODUCTS.DELETE_CONFIRM', { name: item.name_jabvox })
    )
  )
    return;
  try {
    await store.dispatch('jabvoxProducts/destroyDiscount', item.id);
    useAlert(t('JABVOX_PRODUCTS.DELETE_SUCCESS'));
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_PRODUCTS.DISCOUNTS.TITLE') }}
      </h2>
      <Button
        icon="i-lucide-plus"
        :label="$t('JABVOX_PRODUCTS.NEW')"
        @click="openNew"
      />
    </div>

    <div
      v-if="uiFlags.isFetchingDiscounts"
      class="text-sm text-slate-400 animate-pulse py-6 text-center"
    >
      {{ $t('JABVOX_PRODUCTS.LOADING') }}
    </div>
    <div
      v-else-if="discounts.length === 0"
      class="text-sm text-slate-400 text-center py-10"
    >
      {{ $t('JABVOX_PRODUCTS.DISCOUNTS.EMPTY') }}
    </div>

    <table
      v-else
      class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
    >
      <thead>
        <tr class="text-left text-slate-500 dark:text-slate-400">
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.COLS.NAME') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.DISCOUNTS.COLS.PERCENTAGE') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.COLS.STATUS') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.COLS.ACTIONS') }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
        <tr
          v-for="item in discounts"
          :key="item.id"
          class="hover:bg-slate-50 dark:hover:bg-slate-800/50"
        >
          <td class="py-3 pr-4 font-medium text-slate-800 dark:text-slate-100">
            {{ item.name_jabvox }}
          </td>
          <td class="py-3 pr-4 text-slate-700 dark:text-slate-200">
            {{ item.percentage_jabvox }}%
          </td>
          <td class="py-3 pr-4">
            <span
              class="text-xs px-2 py-1 rounded-full font-medium"
              :class="[
                item.active_jabvox
                  ? 'bg-green-100 text-green-700'
                  : 'bg-slate-100 text-slate-500',
              ]"
            >
              {{
                item.active_jabvox
                  ? $t('JABVOX_PRODUCTS.ACTIVE')
                  : $t('JABVOX_PRODUCTS.INACTIVE')
              }}
            </span>
          </td>
          <td class="py-3 pr-4">
            <div class="flex gap-2">
              <Button
                size="small"
                variant="ghost"
                icon="i-lucide-pencil"
                @click="openEdit(item)"
              />
              <Button
                size="small"
                variant="ghost"
                color-scheme="alert"
                icon="i-lucide-trash-2"
                @click="onDelete(item)"
              />
            </div>
          </td>
        </tr>
      </tbody>
    </table>

    <div
      v-if="showForm"
      class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
      @click.self="showForm = false"
    >
      <div
        class="bg-white dark:bg-slate-900 rounded-xl shadow-xl p-6 w-full max-w-md space-y-4"
      >
        <h3 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          {{
            editingItem ? $t('JABVOX_PRODUCTS.EDIT') : $t('JABVOX_PRODUCTS.NEW')
          }}
        </h3>
        <div class="space-y-3">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.COLS.NAME') }} *</label
            >
            <input
              v-model="form.name_jabvox"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.DISCOUNTS.COLS.PERCENTAGE') }}</label
            >
            <input
              v-model="form.percentage_jabvox"
              type="number"
              step="0.01"
              min="0"
              max="100"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.COLS.DESCRIPTION') }}</label
            >
            <textarea
              v-model="form.description_jabvox"
              rows="2"
              class="w-full resize-none rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              v-model="form.active_jabvox"
              type="checkbox"
              class="rounded text-woot-500"
            />
            <span class="text-sm text-slate-700 dark:text-slate-300">{{
              $t('JABVOX_PRODUCTS.ACTIVE')
            }}</span>
          </label>
        </div>
        <div class="flex gap-3 pt-2">
          <Button
            :label="$t('JABVOX_PRODUCTS.SAVE')"
            :is-loading="uiFlags.isSavingDiscount"
            @click="onSubmit"
          />
          <Button
            variant="ghost"
            :label="$t('CANCEL')"
            @click="showForm = false"
          />
        </div>
      </div>
    </div>
  </div>
</template>
