<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const statuses = useMapGetter('jabvoxProducts/getOrderStatusConfigs');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const showForm = ref(false);
const editingItem = ref(null);
const form = ref({
  key_jabvox: '',
  label_jabvox: '',
  sort_order_jabvox: 0,
  color_jabvox: '#6B7280',
});

onMounted(() => store.dispatch('jabvoxProducts/fetchStatus'));

const openNew = () => {
  editingItem.value = null;
  form.value = {
    key_jabvox: '',
    label_jabvox: '',
    sort_order_jabvox: statuses.value.length,
    color_jabvox: '#6B7280',
  };
  showForm.value = true;
};

const openEdit = item => {
  editingItem.value = item;
  form.value = {
    key_jabvox: item.key_jabvox,
    label_jabvox: item.label_jabvox,
    sort_order_jabvox: item.sort_order_jabvox,
    color_jabvox: item.color_jabvox,
  };
  showForm.value = true;
};

const onSubmit = async () => {
  if (!form.value.key_jabvox.trim() || !form.value.label_jabvox.trim()) {
    useAlert(t('JABVOX_PRODUCTS.STATUSES.FORM.REQUIRED'));
    return;
  }
  try {
    if (editingItem.value) {
      await store.dispatch('jabvoxProducts/updateStatus', {
        id: editingItem.value.id,
        ...form.value,
      });
    } else {
      await store.dispatch('jabvoxProducts/createStatus', form.value);
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
      t('JABVOX_PRODUCTS.DELETE_CONFIRM', { name: item.label_jabvox })
    )
  )
    return;
  try {
    await store.dispatch('jabvoxProducts/destroyStatus', item.id);
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
        {{ $t('JABVOX_PRODUCTS.STATUSES.TITLE') }}
      </h2>
      <Button
        icon="i-lucide-plus"
        :label="$t('JABVOX_PRODUCTS.NEW')"
        @click="openNew"
      />
    </div>

    <div
      v-if="uiFlags.isFetchingStatuses"
      class="text-sm text-slate-400 animate-pulse py-6 text-center"
    >
      {{ $t('JABVOX_PRODUCTS.LOADING') }}
    </div>
    <div
      v-else-if="statuses.length === 0"
      class="text-sm text-slate-400 text-center py-10"
    >
      {{ $t('JABVOX_PRODUCTS.STATUSES.EMPTY') }}
    </div>

    <table
      v-else
      class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
    >
      <thead>
        <tr class="text-left text-slate-500 dark:text-slate-400">
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.STATUSES.COLS.KEY') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.STATUSES.COLS.LABEL') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.STATUSES.COLS.COLOR') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.STATUSES.COLS.ORDER') }}
          </th>
          <th class="py-3 pr-4 font-medium">
            {{ $t('JABVOX_PRODUCTS.COLS.ACTIONS') }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
        <tr
          v-for="item in statuses"
          :key="item.id"
          class="hover:bg-slate-50 dark:hover:bg-slate-800/50"
        >
          <td
            class="py-3 pr-4 font-mono text-xs text-slate-600 dark:text-slate-300"
          >
            {{ item.key_jabvox }}
          </td>
          <td class="py-3 pr-4 font-medium text-slate-800 dark:text-slate-100">
            {{ item.label_jabvox }}
          </td>
          <td class="py-3 pr-4">
            <span
              class="inline-block w-5 h-5 rounded-full border border-slate-200"
              :style="{ backgroundColor: item.color_jabvox }"
            />
          </td>
          <td class="py-3 pr-4 text-slate-500">{{ item.sort_order_jabvox }}</td>
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
              >{{ $t('JABVOX_PRODUCTS.STATUSES.COLS.KEY') }} *</label
            >
            <input
              v-model="form.key_jabvox"
              type="text"
              :placeholder="$t('JABVOX_PRODUCTS.STATUSES.FORM.KEY_PLACEHOLDER')"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 font-mono"
            />
          </div>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.STATUSES.COLS.LABEL') }} *</label
            >
            <input
              v-model="form.label_jabvox"
              type="text"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.STATUSES.COLS.COLOR') }}</label
            >
            <input
              v-model="form.color_jabvox"
              type="color"
              class="h-9 w-full rounded-lg border border-slate-200 dark:border-slate-700 cursor-pointer"
            />
          </div>
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >{{ $t('JABVOX_PRODUCTS.STATUSES.COLS.ORDER') }}</label
            >
            <input
              v-model.number="form.sort_order_jabvox"
              type="number"
              min="0"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
          </div>
        </div>
        <div class="flex gap-3 pt-2">
          <Button
            :label="$t('JABVOX_PRODUCTS.SAVE')"
            :is-loading="uiFlags.isSavingStatus"
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
